#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
;  Key & Controller Input Tracker
;  Logs all keyboard and mouse inputs to input_log.txt
; ============================================================

logFile := A_ScriptDir "\input_log.txt"

; Clear log on start
if FileExist(logFile)
    FileDelete(logFile)
FileAppend("=== Input Tracker Started " FormatTime(, "HH:mm:ss") " ===`n", logFile)

ToolTip("Input Tracker ON — logging to input_log.txt")
SetTimer(() => ToolTip(), -3000)

; Install keyboard hook to capture all keys
ih := InputHook("L0 I1 V")
ih.KeyOpt("{All}", "N")
ih.OnKeyDown := LogKeyDown
ih.OnKeyUp := LogKeyUp
ih.Start()

LogKeyDown(ih, vk, sc) {
    global logFile
    name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (name = "")
        name := "??"
    mods := ""
    if GetKeyState("Ctrl")
        mods .= "Ctrl+"
    if GetKeyState("Alt")
        mods .= "Alt+"
    if GetKeyState("Shift")
        mods .= "Shift+"
    if GetKeyState("LWin") || GetKeyState("RWin")
        mods .= "Win+"

    line := FormatTime(, "HH:mm:ss") " DOWN: " mods name " (vk" Format("{:02X}", vk) " sc" Format("{:03X}", sc) ")`n"
    FileAppend(line, logFile)
}

LogKeyUp(ih, vk, sc) {
    global logFile
    name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (name = "")
        name := "??"
    line := FormatTime(, "HH:mm:ss") " UP:   " name " (vk" Format("{:02X}", vk) " sc" Format("{:03X}", sc) ")`n"
    FileAppend(line, logFile)
}

; Also track mouse clicks
~LButton::LogMouse("Left Click")
~RButton::LogMouse("Right Click")
~MButton::LogMouse("Middle Click")

LogMouse(btn) {
    global logFile
    MouseGetPos(&x, &y)
    line := FormatTime(, "HH:mm:ss") " MOUSE: " btn " at " x "," y "`n"
    FileAppend(line, logFile)
}

; Track mouse wheel
~WheelUp::LogWheel("WheelUp")
~WheelDown::LogWheel("WheelDown")

LogWheel(dir) {
    global logFile
    line := FormatTime(, "HH:mm:ss") " MOUSE: " dir "`n"
    FileAppend(line, logFile)
}

^Escape::ExitApp()  ; Ctrl+Escape to stop tracker
