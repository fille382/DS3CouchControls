# DS3 Couch Controls

Use a DualShock 3 controller as a full desktop mouse and keyboard replacement. Navigate Windows, browse the web, dictate text with local AI speech-to-text, and control media — all from your couch.

## Features

- **Mouse cursor** — Left stick with radial deadzone, acceleration curve, and sub-pixel precision
- **Scrolling** — Right stick for smooth vertical and horizontal scrolling
- **Click/Drag** — R2 (left click), L2 (right click), Cross (hold-to-drag)
- **D-Pad navigation** — Arrow keys for navigating files, menus, and lists
- **Voice-to-text** — Hold R1 to dictate using a local Whisper AI model (no cloud, no subscription)
- **Voice commands** — L1+R1 for hands-free keyboard shortcuts ("copy", "paste", "enter", "undo", etc.)
- **Media controls** — L1+D-Pad for next/prev track and volume
- **Alt+Tab** — Select button opens the window switcher with D-Pad navigation
- **Zoom lens** — L3 toggles a circular magnifier with sniper cursor mode
- **Modifier layer** — L1 reveals an on-screen HUD showing all available shortcuts
- **Recording overlay** — Animated sound wave visualization during voice input

## Requirements

- **Windows 10/11**
- **DualShock 3 controller** with [DsHidMini](https://github.com/nefarius/DsHidMini) in XInput mode
- **AutoHotkey v2** — [autohotkey.com](https://www.autohotkey.com/)
- **Python 3.10+** with NVIDIA GPU for voice features
- **Python packages:** `faster-whisper`, `sounddevice`, `numpy`

## Setup

1. Install DsHidMini and pair your DS3 controller (USB or Bluetooth)
2. Set HID device mode to **XInput** in DsHidMini Control
3. Install Python dependencies:
   ```
   pip install faster-whisper sounddevice numpy
   ```
4. Run `DS3Mouse.ahk` — it auto-launches the Whisper server

The first launch downloads the Whisper model (~3GB for large-v3) which may take a few minutes.

## Controls

### Normal Mode

| Input | Action |
|-------|--------|
| Left Stick | Move cursor |
| Right Stick | Scroll |
| R2 | Left click (hold to drag) |
| L2 | Right click (hold to drag) |
| Cross | Left click (hold to drag) |
| Circle | Right click |
| Square | Backspace (hold to repeat) |
| Triangle | Copy / Paste toggle |
| D-Pad | Arrow keys |
| R1 (hold) | Dictate with Whisper |
| Start | Windows Start Menu |
| Select | Alt+Tab window switcher |
| L3 | Sniper mode + Zoom lens |
| R3 | Rapid scroll toggle |
| PS | Pause/Resume script |

### L1 Modifier Layer

| Input | Action |
|-------|--------|
| L1 + Cross | Enter |
| L1 + Circle | Escape |
| L1 + Square | Select All + Delete |
| L1 + Triangle | Tab |
| L1 + D-Up | Volume Up |
| L1 + D-Down | Volume Down |
| L1 + D-Left | Previous Track |
| L1 + D-Right | Next Track |
| L1 + R1 (hold) | Voice command mode |

### Voice Commands

Say these while holding L1+R1:

| Command | Action |
|---------|--------|
| enter | Enter key |
| escape / back | Escape key |
| copy | Ctrl+C |
| paste | Paste |
| cut | Ctrl+X |
| undo | Ctrl+Z |
| redo | Ctrl+Y |
| select all | Ctrl+A |
| delete | Delete key |
| tab | Tab key |
| space | Space key |
| save | Ctrl+S |
| find / search | Ctrl+F |
| close | Alt+F4 |
| play / pause | Media play/pause |
| next / skip | Next track |
| previous | Previous track |
| open browser | Default browser |
| open explorer | File Explorer |
| open spotify | Spotify |
| open discord | Discord |

## Files

| File | Purpose |
|------|---------|
| `DS3Mouse.ahk` | Main controller script (AutoHotkey v2) |
| `whisper_server.py` | Local Whisper speech-to-text server |
| `media_control.py` | Spotify/media control helper |
| `DS3Mouse.ico` | Custom tray icon |
| `DS3Test.ahk` | Controller axis/button tester |

## Configuration

Edit the `Config` class at the top of `DS3Mouse.ahk` to tune:

- `CursorDeadzone` / `CursorMaxSpeed` / `CursorExponent` — mouse sensitivity
- `ScrollDeadzone` / `ScrollMaxSpeed` — scroll behavior
- `SniperDivisor` — slow-aim multiplier
- `DpadRepeatDelay` / `DpadRepeatInterval` — D-Pad repeat timing
- `UserIndex` — XInput controller index (0-3)

## Architecture

- **DS3Mouse.ahk** — AHK v2 script: XInput polling, mouse/keyboard emulation, HUD overlay, recording visualization, zoom lens
- **whisper_server.py** — Python TCP server: records audio, transcribes via faster-whisper on GPU, auto-detects language
- **media_control.py** — Python helper: controls Spotify via Windows COM automation
- Communication via TCP on localhost:7492, audio levels via shared file for the animated overlay

## Known Limitations

- DsHidMini XInput mode sends phantom keyboard events for some buttons — `CleanSend()` workarounds are included
- Bluetooth headset audio drops to mono 16kHz during recording (Bluetooth HFP limitation)
- Whisper large-v3 requires ~3GB VRAM
