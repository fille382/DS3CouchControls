#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
;  Stick vs D-Pad Diagnostic Tool
;  Shows exactly what XInput reports for sticks AND d-pad
;  simultaneously, so we can see when stick movement
;  triggers phantom d-pad events
; ============================================================

class XI {
    static hModule := 0
    static pGetState := 0
    static _buf := Buffer(16, 0)

    static Init() {
        for dll in ["xinput1_4", "xinput1_3", "xinput9_1_0"] {
            XI.hModule := DllCall("LoadLibrary", "Str", dll, "Ptr")
            if XI.hModule
                break
        }
        XI.pGetState := DllCall("GetProcAddress", "Ptr", XI.hModule, "AStr", "XInputGetState", "Ptr")
    }

    static GetState(idx := 0) {
        r := DllCall(XI.pGetState, "UInt", idx, "Ptr", XI._buf, "UInt")
        if (r != 0)
            return {connected: false, buttons: 0, lt: 0, rt: 0, lx: 0, ly: 0, rx: 0, ry: 0}
        return {
            connected: true,
            buttons: NumGet(XI._buf, 4, "UShort"),
            lt:      NumGet(XI._buf, 6, "UChar"),
            rt:      NumGet(XI._buf, 7, "UChar"),
            lx:      NumGet(XI._buf, 8, "Short"),
            ly:      NumGet(XI._buf, 10, "Short"),
            rx:      NumGet(XI._buf, 12, "Short"),
            ry:      NumGet(XI._buf, 14, "Short")
        }
    }
}

XI.Init()

; Find controller
userIdx := 0
loop 4 {
    if XI.GetState(A_Index - 1).connected {
        userIdx := A_Index - 1
        break
    }
}

; Create GUI
g := Gui("+AlwaysOnTop -MaximizeBox", "Stick vs D-Pad Diagnostic")
g.SetFont("s11", "Consolas")
g.BackColor := "0x1a1a2e"

g.SetFont("s14 bold")
g.AddText("cWhite w600", "STICK vs D-PAD DIAGNOSTIC")
g.SetFont("s11 norm")
g.AddText("c888888 w600", "Move the LEFT STICK slowly and watch for phantom d-pad events")
g.AddText("c888888 w600", "Controller index: " userIdx)

g.AddText("cWhite w600", "")
g.SetFont("s12 bold")
g.AddText("c4FC3F7 w600", "LEFT STICK")
g.SetFont("s11 norm")

ctrlLX := g.AddText("cWhite w600", "LX: 0")
ctrlLY := g.AddText("cWhite w600", "LY: 0")
ctrlLMag := g.AddText("cWhite w600", "Magnitude: 0")
ctrlLMagSq := g.AddText("c888888 w600", "Magnitude²: 0")

g.AddText("cWhite w600", "")
g.SetFont("s12 bold")
g.AddText("cFF6B6B w600", "D-PAD (from XInput buttons bitmask)")
g.SetFont("s11 norm")

ctrlDpad := g.AddText("cWhite w600 h30", "D-Pad: NONE")
ctrlDpadBits := g.AddText("c888888 w600", "Raw bits: 0000")
ctrlDpadHex := g.AddText("c888888 w600", "Buttons hex: 0x0000")

g.AddText("cWhite w600", "")
g.SetFont("s12 bold")
g.AddText("cFFD93D w600", "CONFLICT DETECTION")
g.SetFont("s11 norm")

ctrlConflict := g.AddText("c66BB6A w600 h30", "No conflict")
ctrlLog := g.AddEdit("cWhite Background1a1a2e w600 h200 ReadOnly vLog", "")

g.AddText("cWhite w600", "")
g.SetFont("s12 bold")
g.AddText("c4FC3F7 w600", "RIGHT STICK")
g.SetFont("s11 norm")
ctrlRX := g.AddText("cWhite w600", "RX: 0")
ctrlRY := g.AddText("cWhite w600", "RY: 0")

g.AddText("cWhite w600", "")
g.SetFont("s12 bold")
g.AddText("c4FC3F7 w600", "TRIGGERS")
g.SetFont("s11 norm")
ctrlLT := g.AddText("cWhite w600", "LT: 0")
ctrlRT := g.AddText("cWhite w600", "RT: 0")

g.AddText("cWhite w600", "")
g.SetFont("s12 bold")
g.AddText("cFF6B6B w600", "ALL BUTTONS")
g.SetFont("s11 norm")
ctrlBtns := g.AddText("cWhite w600 h60", "")

g.Show("w640")

logText := ""
logCount := 0
prevDpad := 0

SetTimer(Poll, 10)

Poll() {
    global ctrlLX, ctrlLY, ctrlLMag, ctrlLMagSq
    global ctrlDpad, ctrlDpadBits, ctrlDpadHex
    global ctrlConflict, ctrlLog
    global ctrlRX, ctrlRY, ctrlLT, ctrlRT, ctrlBtns
    global logText, logCount, prevDpad, userIdx

    gp := XI.GetState(userIdx)
    if !gp.connected
        return

    lx := gp.lx
    ly := gp.ly
    mag := Sqrt(lx * lx + ly * ly)
    magSq := lx * lx + ly * ly

    ; Left stick
    ctrlLX.Text := "LX: " lx "  " MakeBar(lx, 32767)
    ctrlLY.Text := "LY: " ly "  " MakeBar(ly, 32767)
    ctrlLMag.Text := "Magnitude: " Round(mag) " / 32767  (" Round(mag / 327.67) "%)"
    ctrlLMagSq.Text := "Magnitude²: " magSq

    ; D-pad
    dpad := gp.buttons & 0x000F
    dpadStr := ""
    if (dpad & 0x0001)
        dpadStr .= "UP "
    if (dpad & 0x0002)
        dpadStr .= "DOWN "
    if (dpad & 0x0004)
        dpadStr .= "LEFT "
    if (dpad & 0x0008)
        dpadStr .= "RIGHT "
    if (dpadStr = "")
        dpadStr := "NONE"

    ctrlDpad.Text := "D-Pad: " dpadStr
    ctrlDpadBits.Text := "Raw bits: " Format("{:04b}", dpad)
    ctrlDpadHex.Text := "Buttons hex: " Format("0x{:04X}", gp.buttons)

    ; Conflict detection
    if (dpad != 0 && mag > 1000) {
        ctrlConflict.Text := "!! CONFLICT: Stick active (mag=" Round(mag) ") + D-pad=" dpadStr
        ctrlConflict.SetFont("cFF4444")

        ; Log the conflict
        if (dpad != prevDpad) {
            logCount += 1
            timestamp := FormatTime(, "HH:mm:ss")
            logText := timestamp " | CONFLICT #" logCount ": Stick mag=" Round(mag) " dpad=" dpadStr " LX=" lx " LY=" ly "`r`n" logText
            if (StrLen(logText) > 5000)
                logText := SubStr(logText, 1, 5000)
            ctrlLog.Value := logText
        }
    } else if (dpad != 0) {
        ctrlConflict.Text := "D-Pad pressed (stick idle) — REAL press"
        ctrlConflict.SetFont("c66BB6A")
    } else {
        ctrlConflict.Text := "No conflict"
        ctrlConflict.SetFont("c66BB6A")
    }
    prevDpad := dpad

    ; Right stick
    ctrlRX.Text := "RX: " gp.rx "  " MakeBar(gp.rx, 32767)
    ctrlRY.Text := "RY: " gp.ry "  " MakeBar(gp.ry, 32767)

    ; Triggers
    ctrlLT.Text := "LT: " gp.lt "  " MakeBar(gp.lt, 255)
    ctrlRT.Text := "RT: " gp.rt "  " MakeBar(gp.rt, 255)

    ; All buttons
    btns := gp.buttons
    btnStr := ""
    if (btns & 0x0010) btnStr .= "START "
    if (btns & 0x0020) btnStr .= "BACK "
    if (btns & 0x0040) btnStr .= "L3 "
    if (btns & 0x0080) btnStr .= "R3 "
    if (btns & 0x0100) btnStr .= "L1 "
    if (btns & 0x0200) btnStr .= "R1 "
    if (btns & 0x0400) btnStr .= "GUIDE "
    if (btns & 0x1000) btnStr .= "A "
    if (btns & 0x2000) btnStr .= "B "
    if (btns & 0x4000) btnStr .= "X "
    if (btns & 0x8000) btnStr .= "Y "
    if (btnStr = "")
        btnStr := "NONE"
    ctrlBtns.Text := btnStr
}

MakeBar(val, maxVal) {
    ; ASCII bar graph
    normalized := Abs(val) / maxVal
    len := Round(normalized * 20)
    bar := ""
    loop len
        bar .= "|"
    loop 20 - len
        bar .= "."
    sign := (val >= 0) ? "+" : "-"
    return "[" sign bar "]"
}

g.OnEvent("Close", (*) => ExitApp())
