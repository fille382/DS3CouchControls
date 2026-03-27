"""
DS3Mouse Whisper Server
TCP server that records audio from mic and transcribes with faster-whisper on GPU.

Protocol (TCP localhost:7492):
  Client sends: START\n  → server begins recording
  Client sends: STOP\n   → server stops recording, transcribes, replies TEXT:<text>\n
  Server sends: READY\n  → on connect, indicates model is loaded
"""

import os
import socket
import threading
import sys
import io

# Add NVIDIA CUDA DLLs to PATH before importing anything that needs them
try:
    import nvidia.cublas
    import nvidia.cudnn
    for mod in [nvidia.cublas, nvidia.cudnn]:
        bin_dir = os.path.join(mod.__path__[0], "bin")
        if os.path.isdir(bin_dir):
            os.add_dll_directory(bin_dir)
            os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")
except ImportError:
    pass  # CUDA libs not installed, will fall back to CPU

import numpy as np
import sounddevice as sd
from faster_whisper import WhisperModel

# ── Config ──
HOST = "127.0.0.1"
PORT = 7492
SAMPLE_RATE = 16000  # Whisper expects 16kHz
CHANNELS = 1
MODEL_SIZE = "large-v3"
DEVICE = "cuda"       # Use "cpu" if no NVIDIA GPU
COMPUTE_TYPE = "float16"  # float16 for GPU, int8 for CPU

# Auto-detect best input device (prefer WASAPI for lowest latency)
def find_input_device():
    """Find the best available input device."""
    devices = sd.query_devices()

    # Priority: WASAPI > DirectSound > MME
    candidates = []
    for i, dev in enumerate(devices):
        if dev['max_input_channels'] > 0:
            if 'WASAPI' in dev['name']:
                priority = 0
            elif 'DirectSound' in dev['name']:
                priority = 1
            elif 'MME' in dev['name']:
                priority = 2
            else:
                priority = 3
            candidates.append((priority, i, dev))

    if not candidates:
        print("ERROR: No input device found!")
        sys.exit(1)

    candidates.sort()
    _, idx, dev = candidates[0]
    ch = min(dev['max_input_channels'], CHANNELS)
    print(f"Using input device {idx}: {dev['name']} ({ch}ch)")
    return idx, ch

INPUT_DEVICE, INPUT_CHANNELS = find_input_device()

# ── Globals ──
model = None
recording = False
audio_chunks = []
record_lock = threading.Lock()
current_rms = 0.0  # Live audio level for visualization
audio_stream = None  # Opened on-demand, closed after recording
# Language memory — tracks last N detected languages to auto-select
_language_history = []
_LANGUAGE_MEMORY = 3  # How many recent detections to remember


def load_model():
    """Load Whisper model (runs once at startup)."""
    global model
    print(f"Loading Whisper '{MODEL_SIZE}' model on {DEVICE}...")
    model = WhisperModel(MODEL_SIZE, device=DEVICE, compute_type=COMPUTE_TYPE)
    print("Model loaded and ready!")


LEVEL_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "whisper_level.txt")
# Pre-open level file handle to avoid open/close overhead every callback
_level_fd = None
_last_level_write = 0.0
import time as _time

def _ensure_level_fd():
    """Open (or reopen) the level file for direct writes."""
    global _level_fd
    try:
        _level_fd = os.open(LEVEL_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
    except:
        _level_fd = None

_ensure_level_fd()

def audio_callback(indata, frames, time_info, status):
    """Called by sounddevice for each audio chunk during recording."""
    global current_rms, _last_level_write, _level_fd
    if status:
        print(f"Audio status: {status}", file=sys.stderr)
    if recording:
        audio_chunks.append(indata.copy())
        # Calculate RMS for live visualization (0.0 to 1.0)
        rms = float(np.sqrt(np.mean(indata ** 2)))
        # Amplify and clamp to 0-1 range (Bluetooth mics are quiet)
        current_rms = min(1.0, rms * 20.0)
        # Throttle file writes to ~15fps (every 66ms) to match overlay refresh
        now = _time.monotonic()
        if now - _last_level_write >= 0.066:
            _last_level_write = now
            try:
                if _level_fd is not None:
                    data = f"{current_rms:.3f}".encode()
                    os.lseek(_level_fd, 0, os.SEEK_SET)
                    os.write(_level_fd, data)
                    os.ftruncate(_level_fd, len(data))
            except:
                _ensure_level_fd()


def start_recording():
    """Start capturing audio — opens mic stream on demand."""
    global recording, audio_chunks, audio_stream
    with record_lock:
        audio_chunks = []
        recording = True
    # Open audio stream (triggers Bluetooth HFP switch)
    audio_stream = sd.InputStream(
        device=INPUT_DEVICE,
        samplerate=SAMPLE_RATE,
        channels=INPUT_CHANNELS,
        dtype="float32",
        callback=audio_callback,
        blocksize=int(SAMPLE_RATE * 0.1),
    )
    audio_stream.start()
    print("Recording started (mic stream opened)...")


def stop_and_transcribe(force_language=None):
    """Stop recording, close mic stream, transcribe. force_language overrides auto-detect."""
    global recording, audio_stream
    with record_lock:
        recording = False
    # Close audio stream immediately — releases Bluetooth back to A2DP
    if audio_stream is not None:
        try:
            audio_stream.stop()
            audio_stream.close()
        except:
            pass
        audio_stream = None
        print("Mic stream closed (audio quality restored).")

    if not audio_chunks:
        print("No audio captured.")
        return ""

    # Concatenate all chunks into a single numpy array
    audio_data = np.concatenate(audio_chunks, axis=0).flatten()

    # Ensure float32 in range [-1, 1]
    if audio_data.dtype != np.float32:
        audio_data = audio_data.astype(np.float32)

    duration = len(audio_data) / SAMPLE_RATE
    print(f"Recording stopped. Duration: {duration:.1f}s")

    if duration < 0.3:
        print("Too short, skipping.")
        return ""

    # Amplify audio — Bluetooth mics are often quiet
    peak = np.max(np.abs(audio_data))
    if peak > 0:
        # Normalize to ~80% volume
        audio_data = audio_data * (0.8 / peak)

    # Determine language hint
    global _language_history
    if force_language:
        language_hint = force_language
    else:
        language_hint = None
        if len(_language_history) >= 2:
            from collections import Counter
            counts = Counter(_language_history[-_LANGUAGE_MEMORY:])
            most_common, count = counts.most_common(1)[0]
            if count >= 2:
                language_hint = most_common

    # Transcribe
    transcribe_kwargs = dict(
        beam_size=5,
        vad_filter=True,
        vad_parameters=dict(
            threshold=0.3,
            min_silence_duration_ms=500,
            speech_pad_ms=300,
        ),
    )

    if language_hint:
        transcribe_kwargs["language"] = language_hint
        print(f"Transcribing (language: {language_hint}{' [forced]' if force_language else ''})...")
    else:
        print("Transcribing (auto-detect language)...")

    segments, info = model.transcribe(audio_data, **transcribe_kwargs)
    text = " ".join(seg.text.strip() for seg in segments).strip()

    # Update language history (skip for forced language — don't pollute history)
    detected_lang = info.language
    if not force_language:
        _language_history.append(detected_lang)
        if len(_language_history) > _LANGUAGE_MEMORY * 2:
            _language_history = _language_history[-_LANGUAGE_MEMORY:]

    print(f"Language: {detected_lang} ({info.language_probability:.0%}) | History: {_language_history}")
    print(f"Transcribed: {text}")
    return text


def handle_client(conn, addr):
    """Handle a single TCP client connection."""
    print(f"Client connected: {addr}")
    try:
        # Signal that we're ready
        conn.sendall(b"READY\n")

        buf = b""
        while True:
            data = conn.recv(1024)
            if not data:
                break
            buf += data

            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                cmd = line.decode("utf-8").strip().upper()

                if cmd == "START":
                    start_recording()
                    conn.sendall(b"OK\n")

                elif cmd == "STOP" or cmd == "STOP_EN":
                    # STOP_EN forces English (for voice commands)
                    force_lang = "en" if cmd == "STOP_EN" else None
                    text = stop_and_transcribe(force_language=force_lang)
                    # Write result to file for non-blocking AHK pickup
                    result_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "whisper_result.txt")
                    with open(result_path, "w", encoding="utf-8") as f:
                        f.write(text)
                    response = f"TEXT:{text}\n"
                    conn.sendall(response.encode("utf-8"))

                elif cmd == "PING":
                    conn.sendall(b"PONG\n")

                elif cmd == "QUIT":
                    conn.sendall(b"BYE\n")
                    return

    except (ConnectionResetError, BrokenPipeError):
        print(f"Client disconnected: {addr}")
    finally:
        # Make sure recording stops if client disconnects
        global recording
        recording = False
        conn.close()


def main():
    # Load model first
    load_model()

    # Audio stream is now opened on-demand in start_recording()
    # This prevents Bluetooth from permanently switching to low-quality HFP mode
    print("Audio stream: on-demand (preserves Bluetooth A2DP quality)")

    # Start TCP server
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(2)
    print(f"Whisper server listening on {HOST}:{PORT}")

    try:
        while True:
            conn, addr = server.accept()
            # Handle each client in a thread
            t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
            t.start()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        if audio_stream is not None:
            try:
                audio_stream.stop()
                audio_stream.close()
            except:
                pass
        server.close()


if __name__ == "__main__":
    main()
