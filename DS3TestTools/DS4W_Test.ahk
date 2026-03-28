#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
;  DS4W Detection Test
;  Tests all methods to read a DS4W-mode controller:
;  1. AHK built-in Joystick (DirectInput)
;  2. XInput
;  3. Raw HID
; ============================================================

; ── Test 1: AHK DirectInput ──
TestDirectInput() {
    result := ""
    loop 16 {
        name := GetKeyState(A_Index "JoyName")
        if (name != "") {
            id := GetKeyState(A_Index "JoyInfo")
            buttons := GetKeyState(A_Index "JoyButtons")
            x := GetKeyState(A_Index "JoyX")
            y := GetKeyState(A_Index "JoyY")
            z := GetKeyState(A_Index "JoyZ")
            r := GetKeyState(A_Index "JoyR")
            u := GetKeyState(A_Index "JoyU")
            v := GetKeyState(A_Index "JoyV")
            pov := GetKeyState(A_Index "JoyPOV")
            result .= "  Joy" A_Index ": " name "`n"
            result .= "    Info: " id " | Buttons: " buttons "`n"
            result .= "    X=" Round(x,1) " Y=" Round(y,1) " Z=" Round(z,1) "`n"
            result .= "    R=" Round(r,1) " U=" Round(u,1) " V=" Round(v,1) "`n"
            result .= "    POV=" pov "`n"
        }
    }
    return result = "" ? "  No joysticks found via DirectInput`n" : result
}

; ── Test 2: XInput ──
TestXInput() {
    result := ""
    hModule := 0
    for dll in ["xinput1_4", "xinput1_3", "xinput9_1_0"] {
        hModule := DllCall("LoadLibrary", "Str", dll, "Ptr")
        if hModule {
            result .= "  Loaded: " dll "`n"
            break
        }
    }
    if !hModule
        return "  Could not load XInput DLL`n"

    pGetState := DllCall("GetProcAddress", "Ptr", hModule, "AStr", "XInputGetState", "Ptr")
    if !pGetState
        return "  Could not find XInputGetState`n"

    state := Buffer(16, 0)
    loop 4 {
        idx := A_Index - 1
        r := DllCall(pGetState, "UInt", idx, "Ptr", state, "UInt")
        if (r = 0) {
            buttons := NumGet(state, 4, "UShort")
            lt := NumGet(state, 6, "UChar")
            rt := NumGet(state, 7, "UChar")
            lx := NumGet(state, 8, "Short")
            ly := NumGet(state, 10, "Short")
            rx := NumGet(state, 12, "Short")
            ry := NumGet(state, 14, "Short")
            result .= "  Index " idx ": CONNECTED`n"
            result .= "    Buttons: 0x" Format("{:04X}", buttons) "`n"
            result .= "    LT=" lt " RT=" rt "`n"
            result .= "    LX=" lx " LY=" ly " RX=" rx " RY=" ry "`n"
        } else {
            result .= "  Index " idx ": not connected`n"
        }
    }
    return result
}

; ── Test 3: HID Device Enumeration ──
TestHID() {
    result := ""
    ; Use SetupAPI to list HID devices
    try {
        hHID := DllCall("hid\HidD_GetHidGuid", "Ptr", guid := Buffer(16, 0))
        ; Simplified — just check if any HID game controllers exist
        loop 20 {
            try {
                name := GetKeyState(A_Index "JoyName")
                if name != ""
                    result .= "  HID Joy" A_Index ": " name "`n"
            }
        }
    }
    if result = ""
        result := "  (HID enumeration limited — see DirectInput results above)`n"
    return result
}

; ── Build GUI ──
g := Gui("+AlwaysOnTop -MaximizeBox", "DS4W Detection Test")
g.SetFont("s10", "Consolas")
g.BackColor := "1a1a2e"

g.SetFont("s14 bold c00FFFF")
g.AddText("w700", "DS4W CONTROLLER DETECTION")
g.SetFont("s10 norm cFFFFFF")

g.AddText("w700 cFFFF00", "═══ DirectInput (AHK Built-in) ═══")
diCtrl := g.AddText("w700 h120 cFFFFFF", "Scanning...")

g.AddText("w700 cFFFF00", "═══ XInput ═══")
xiCtrl := g.AddText("w700 h100 cFFFFFF", "Scanning...")

g.AddText("w700 cFFFF00", "═══ HID Devices ═══")
hidCtrl := g.AddText("w700 h60 cFFFFFF", "Scanning...")

g.AddText("w700 c88FF88", "═══ Live Input (updates every 100ms) ═══")
liveCtrl := g.AddText("w700 h140 cFFFFFF", "Waiting...")

g.Show()

; ── Initial scan ──
diCtrl.Text := TestDirectInput()
xiCtrl.Text := TestXInput()
hidCtrl.Text := TestHID()

; ── Live update timer ──
SetTimer(UpdateLive, 100)

UpdateLive() {
    ; Try DirectInput first
    diText := ""
    loop 16 {
        name := GetKeyState(A_Index "JoyName")
        if (name != "") {
            x := Round(GetKeyState(A_Index "JoyX"), 1)
            y := Round(GetKeyState(A_Index "JoyY"), 1)
            z := Round(GetKeyState(A_Index "JoyZ"), 1)
            r := Round(GetKeyState(A_Index "JoyR"), 1)
            u := Round(GetKeyState(A_Index "JoyU"), 1)
            pov := GetKeyState(A_Index "JoyPOV")

            ; Read buttons
            btnStr := ""
            loop 20 {
                if GetKeyState(A_Index "Joy" A_Index)
                    btnStr .= A_Index " "
            }

            diText .= "DI Joy" A_Index " [" name "]:`n"
            diText .= "  X=" x " Y=" y " Z=" z " R=" r " U=" u " POV=" pov "`n"
            if btnStr != ""
                diText .= "  Buttons: " btnStr "`n"
            break
        }
    }

    ; Try XInput
    xiText := ""
    static hMod := DllCall("LoadLibrary", "Str", "xinput1_4", "Ptr")
    static pGS := hMod ? DllCall("GetProcAddress", "Ptr", hMod, "AStr", "XInputGetState", "Ptr") : 0
    if pGS {
        state := Buffer(16, 0)
        loop 4 {
            idx := A_Index - 1
            if (DllCall(pGS, "UInt", idx, "Ptr", state, "UInt") = 0) {
                btn := NumGet(state, 4, "UShort")
                lt := NumGet(state, 6, "UChar")
                rt := NumGet(state, 7, "UChar")
                lx := NumGet(state, 8, "Short")
                ly := NumGet(state, 10, "Short")
                rx := NumGet(state, 12, "Short")
                ry := NumGet(state, 14, "Short")
                xiText .= "XI[" idx "] Btn=0x" Format("{:04X}", btn)
                xiText .= " LT=" lt " RT=" rt
                xiText .= " LX=" lx " LY=" ly " RX=" rx " RY=" ry "`n"
            }
        }
    }

    text := ""
    if diText != ""
        text .= "── DirectInput ──`n" diText
    if xiText != ""
        text .= "── XInput ──`n" xiText
    if text = ""
        text := "No controller detected via DirectInput or XInput"

    liveCtrl.Text := text
}
