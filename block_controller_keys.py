"""
Block DsHidMini XInput keyboard events.
DsHidMini in XInput mode sends controller buttons as real keyboard VK codes
which interfere with normal operation. This script installs a low-level
keyboard hook to suppress those VK codes.

Run with: pythonw block_controller_keys.py (hidden) or python block_controller_keys.py (visible)
"""

import ctypes
import ctypes.wintypes as wt
import sys

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32

# VK codes sent by DsHidMini XInput driver
BLOCKED_VKS = {
    0xC3,  # Controller button
    0xC8,  # L1 (appears as LControl)
    0xCB,  # D-pad Left
    0xCC,  # D-pad Up
    0xCD,  # D-pad Right
    0xCE,  # D-pad Down
    0xD3,  # Controller button
    0xD5,  # Controller button
    0xD6,  # Controller button
    0xAA,  # Browser_Search
}

# KBDLLHOOKSTRUCT
class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [
        ("vkCode", wt.DWORD),
        ("scanCode", wt.DWORD),
        ("flags", wt.DWORD),
        ("time", wt.DWORD),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]

# Hook type
HOOKPROC = ctypes.CFUNCTYPE(ctypes.c_long, ctypes.c_int, wt.WPARAM, ctypes.POINTER(KBDLLHOOKSTRUCT))
WH_KEYBOARD_LL = 13

blocked_count = 0

@HOOKPROC
def low_level_keyboard_proc(nCode, wParam, lParam):
    global blocked_count
    if nCode >= 0:
        vk = lParam.contents.vkCode
        if vk in BLOCKED_VKS:
            blocked_count += 1
            return 1  # Block the key
    return user32.CallNextHookEx(None, nCode, wParam, lParam)

def main():
    print("Installing low-level keyboard hook to block DsHidMini VK codes...")
    print(f"Blocking VK codes: {', '.join(f'0x{v:02X}' for v in sorted(BLOCKED_VKS))}")

    hook = user32.SetWindowsHookExW(WH_KEYBOARD_LL, low_level_keyboard_proc, None, 0)
    if not hook:
        print(f"Failed to install hook! Error: {kernel32.GetLastError()}")
        sys.exit(1)

    print("Hook installed. Controller keyboard events are now blocked.")
    print("Press Ctrl+C to stop.\n")

    # Message loop (required for hooks to work)
    msg = wt.MSG()
    try:
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) != 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
    except KeyboardInterrupt:
        pass
    finally:
        user32.UnhookWindowsHookEx(hook)
        print(f"\nHook removed. Blocked {blocked_count} controller key events total.")

if __name__ == "__main__":
    main()
