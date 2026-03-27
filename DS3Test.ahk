#Requires AutoHotkey v2.0
#SingleInstance Force

; Find all connected joysticks
loop 16 {
    name := GetKeyState(A_Index "JoyName")
    if (name != "")
        MsgBox("Joystick " A_Index ": " name)
}

; Show live axes and buttons for joystick 1-4
SetTimer(ShowState, 50)

ShowState() {
    text := ""
    loop 4 {
        id := A_Index
        name := GetKeyState(id "JoyName")
        if (name = "")
            continue
        text .= "=== Joystick " id ": " name " ===`n"
        text .= "X: " Round(GetKeyState(id "JoyX"), 1) "`n"
        text .= "Y: " Round(GetKeyState(id "JoyY"), 1) "`n"
        text .= "Z: " Round(GetKeyState(id "JoyZ"), 1) "`n"
        text .= "R: " Round(GetKeyState(id "JoyR"), 1) "`n"
        text .= "U: " Round(GetKeyState(id "JoyU"), 1) "`n"
        text .= "V: " Round(GetKeyState(id "JoyV"), 1) "`n"
        text .= "POV: " GetKeyState(id "JoyPOV") "`n"

        btns := ""
        loop 32 {
            if GetKeyState(id "Joy" A_Index)
                btns .= A_Index " "
        }
        text .= "Buttons: " (btns = "" ? "none" : btns) "`n`n"
    }
    ToolTip(text = "" ? "No joystick found" : text)
}
