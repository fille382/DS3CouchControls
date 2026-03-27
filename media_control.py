"""
Spotify Desktop media control via Windows AppCommand messages.
Sends WM_APPCOMMAND directly to Spotify window — no keyboard events needed.

Usage:
  python media_control.py next
  python media_control.py prev
  python media_control.py play
"""
import ctypes
import ctypes.wintypes as wt
import subprocess
import sys

user32 = ctypes.windll.user32

# WM_APPCOMMAND constants
WM_APPCOMMAND = 0x0319
APPCOMMAND_MEDIA_NEXTTRACK = 11
APPCOMMAND_MEDIA_PREVIOUSTRACK = 12
APPCOMMAND_MEDIA_PLAY_PAUSE = 14

WNDENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)

def find_spotify():
    """Find Spotify main window by finding Spotify.exe PIDs and their visible windows."""
    # Get Spotify PIDs
    try:
        out = subprocess.check_output(
            ['tasklist', '/FI', 'IMAGENAME eq Spotify.exe', '/FO', 'CSV', '/NH'],
            text=True, creationflags=0x08000000  # CREATE_NO_WINDOW
        )
    except:
        return None

    pids = set()
    for line in out.strip().split('\n'):
        parts = line.strip().strip('"').split('","')
        if len(parts) >= 2:
            try:
                pids.add(int(parts[1]))
            except:
                pass

    if not pids:
        return None

    # Find visible window from Spotify PIDs with Chrome_WidgetWin class
    result = []
    def callback(hwnd, lparam):
        pid = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value in pids and user32.IsWindowVisible(hwnd):
            cls = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, cls, 256)
            if 'Chrome_WidgetWin' in cls.value:
                result.append(hwnd)
        return True

    user32.EnumWindows(WNDENUMPROC(callback), 0)
    return result[0] if result else None

def send_appcommand(hwnd, cmd):
    """Send WM_APPCOMMAND to a window."""
    lparam = cmd << 16
    user32.SendMessageW(hwnd, WM_APPCOMMAND, hwnd, lparam)

def main():
    cmd = sys.argv[1].lower() if len(sys.argv) > 1 else ""

    hwnd = find_spotify()
    if not hwnd:
        print("Spotify not found")
        sys.exit(1)

    if cmd in ("next", "skip"):
        send_appcommand(hwnd, APPCOMMAND_MEDIA_NEXTTRACK)
        print("Next track")
    elif cmd in ("prev", "previous", "back"):
        send_appcommand(hwnd, APPCOMMAND_MEDIA_PREVIOUSTRACK)
        print("Previous track")
    elif cmd in ("play", "pause", "toggle"):
        send_appcommand(hwnd, APPCOMMAND_MEDIA_PLAY_PAUSE)
        print("Play/Pause")
    else:
        print("Usage: python media_control.py [next|prev|play]")

if __name__ == "__main__":
    main()
