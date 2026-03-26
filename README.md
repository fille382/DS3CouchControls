# DS3 Couch Controls

Use a DualShock 3 controller as a full desktop mouse + keyboard replacement, with built-in voice-to-text powered by a local Whisper AI model running on your GPU. No subscriptions, no cloud — everything runs locally.

## Features

- **Mouse control** via left analog stick with radial deadzone, acceleration curve, sub-pixel accumulation, and sniper mode
- **Smooth scrolling** via right analog stick (vertical + horizontal)
- **Voice-to-text** — hold R1 to dictate, powered by [faster-whisper](https://github.com/SYSTRAN/faster-whisper) running locally on CUDA GPU
- **Animated recording overlay** — GDI+ rendered pill-shaped indicator with reactive sound bars
- **Auto-send** — automatically presses Enter after dictation completes (keyboard idle detection)
- **Copy/Paste toggle** — Triangle alternates between Ctrl+C and Ctrl+V
- **Modifier layer** — hold L1 to access secondary functions with on-screen HUD
- **D-Pad navigation** — arrow keys with hold-to-repeat, debounced to prevent double-triggers
- **Full XInput support** — works with DsHidMini in XInput mode over Bluetooth

## Requirements

- **Windows 11**
- **AutoHotkey v2.0+** — https://www.autohotkey.com/
- **Python 3.10+** with CUDA support
- **NVIDIA GPU** (for fast Whisper transcription)
- **DsHidMini** — DS3 driver: https://github.com/nefarius/DsHidMini (set to XInput mode)

## Setup

1. Install AutoHotkey v2 and Python 3.10+

2. Install Python dependencies:
   ```
   pip install -r requirements.txt
   ```

3. Make sure your DS3 is connected via DsHidMini in **XInput mode**

4. Run the script:
   ```
   DS3Mouse.ahk
   ```
   The script will automatically launch the Whisper server and load the model (first run downloads ~3GB).

## Controls

### Normal Mode

| Button | Action |
|--------|--------|
| Left Stick | Move mouse cursor |
| Right Stick | Scroll (vertical & horizontal) |
| R2 | Left click (hold to drag) |
| L2 | Right click (hold to drag) |
| Cross / A | Left click (hold to drag) |
| Circle / B | Right click |
| Triangle / Y | Copy / Paste (toggles) |
| Square / X | Backspace (hold to repeat) |
| D-Pad | Arrow keys |
| R1 (hold) | Voice dictate (Whisper) |
| Start | Enter |
| Select | Escape |
| L3 | Toggle sniper mode |
| R3 | Toggle rapid scroll |
| PS / Guide | Pause / Resume |

### L1 Modifier Layer (hold L1)

| Button | Action |
|--------|--------|
| Cross | Enter |
| Circle | Escape |
| Square | Select All + Delete |
| Triangle | Tab |
| D-Up | Page Up |
| D-Down | Page Down |
| D-Left | Home |
| D-Right | End |
| R1 | Middle click |

## Configuration

Edit the `Config` class at the top of `DS3Mouse.ahk` to tune:

- `CursorDeadzone` / `CursorMaxSpeed` / `CursorExponent` — mouse sensitivity
- `ScrollDeadzone` / `ScrollMaxSpeed` — scroll behavior
- `SniperDivisor` — slow-aim multiplier
- `DpadRepeatDelay` / `DpadRepeatInterval` — D-Pad repeat timing
- `UserIndex` — XInput controller index (0-3)

## Architecture

- **DS3Mouse.ahk** — Main AHK v2 script handling input polling, mouse/keyboard emulation, HUD overlay, and recording visualization
- **whisper_server.py** — Python TCP server that records audio and transcribes via faster-whisper on GPU
- Communication is via TCP on localhost:7492, with audio levels passed through a shared file for the animated overlay

## Notes

- The Whisper model (`large-v3`) is downloaded automatically on first run (~3GB)
- Bluetooth headset microphones will temporarily switch to HFP mode (lower audio quality) during recording — this is a Bluetooth limitation, not a bug. Consider using a USB microphone for dictation to avoid this.
- The script uses XInput directly via DLL calls for minimal latency (~5ms polling)
- GDI+ overlay is optimized with pre-cached brushes, paths, and a sin lookup table to avoid impacting input responsiveness
