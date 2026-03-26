#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
;  DS3Mouse — DualShock 3 (XInput via DsHidMini) as Mouse
; ============================================================
;
;  Controls:
;    Left Stick ............ Mouse cursor
;    Right Stick ........... Scroll (vertical & horizontal)
;    L2 .................... Right click (hold to drag)
;    R2 .................... Left click (hold to drag)
;    R1 (hold) ............. Dictate (Wispr Flow)
;    L1 (hold) ............. Modifier layer + HUD
;    Cross / A ............. Left click / hold to drag (Enter with L1)
;    Circle / B ............ Right click (Escape with L1)
;    Square / X ............ Backspace, hold to repeat (Clear All with L1)
;    Triangle / Y .......... Copy/Paste toggle (Tab with L1)
;    D-Pad Up/Down ......... Scroll wheel up/down (PgUp/PgDn with L1)
;    D-Pad Left/Right ...... Browser back/fwd (Home/End with L1)
;    L3 .................... Toggle sniper mode
;    R3 .................... Toggle rapid scroll
;    Start ................. Enter
;    Back / Select ......... Escape
;    Guide / PS ............ Toggle mouse on/off
;
; ============================================================

; ── Configuration ──
class Config {
    static PollRate := 5

    static UserIndex := 0

    static CursorDeadzone := 3000
    static CursorMaxSpeed := 30
    static CursorMinSpeed := 0.4
    static CursorExponent := 1.8

    static SniperDivisor := 5

    static ScrollDeadzone := 5000
    static ScrollMaxSpeed := 6.0
    static ScrollMinSpeed := 0.3
    static ScrollExponent := 1.6
    static DpadScrollLines := 5
    static DpadRepeatDelay := 300     ; ms before repeat starts
    static DpadRepeatInterval := 80   ; ms between repeats once started

    static TriggerThreshold := 100

    static DictateEnterDelay := 1500  ; ms to wait after text typed before sending Enter

    ; Whisper server
    static WhisperPort := 7492
    static WhisperHost := "127.0.0.1"
}

; ── Runtime state ──
class State {
    static Active := true
    static Sniper := false
    static RapidScroll := false
    static L2Down := false
    static R2Down := false
    static MoveAccumX := 0.0
    static MoveAccumY := 0.0
    static ScrollAccumV := 0.0
    static ScrollAccumH := 0.0
    static DpadScrollTick := 0
    static DpadRepeating := false
    static DpadReleaseCount := 0
    static DpadConfirmedRelease := true
    static LastDpad := 0
    static PrevButtons := 0
    static PrevL3 := false
    static PrevR3 := false
    static PrevGuide := false
    static PrevL1 := false
    static CrossDown := false
    static R1Dictating := false
    static WaitingForTranscription := false
    static SquareHeld := false
    static SquareRepeatTick := 0
    static TriangleNextPaste := false  ; false = next press copies, true = next press pastes
}

; ============================================================
;  L1 overlay HUD
; ============================================================
class HUD {
    static gui := 0
    static visible := false
    static xPos := 0
    static yPos := 0

    static Init() {
        HUD.gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        HUD.gui.BackColor := "0x1a1a2e"
        HUD.gui.MarginX := 10
        HUD.gui.MarginY := 8
        HUD.gui.SetFont("s9", "Consolas")

        modText := ""
        modText .= " L1 + MODIFIER LAYER`n"
        modText .= " ────────────────────────`n"
        modText .= " Cross ........ Enter`n"
        modText .= " Circle ....... Escape`n"
        modText .= " Square ....... Clear All`n"
        modText .= " Triangle ..... Tab`n"
        modText .= " ────────────────────────`n"
        modText .= " D-Up ......... Page Up`n"
        modText .= " D-Down ....... Page Down`n"
        modText .= " D-Left ....... Home`n"
        modText .= " D-Right ...... End`n"
        modText .= " R1 ........... Middle Click"

        HUD.gui.AddText("cWhite Section", modText)

        normText := ""
        normText .= " NORMAL CONTROLS`n"
        normText .= " ────────────────────────`n"
        normText .= " L-Stick ...... Mouse`n"
        normText .= " R-Stick ...... Scroll`n"
        normText .= " L2 ........... Right Click`n"
        normText .= " R2 ........... Left Click`n"
        normText .= " D-Pad ........ Arrow Keys`n"
        normText .= " ────────────────────────`n"
        normText .= " Cross ........ Left Click`n"
        normText .= " Circle ....... Right Click`n"
        normText .= " Square ....... Backspace`n"
        normText .= " Triangle ..... Copy/Paste`n"
        normText .= " R1 (hold) .... Dictate`n"
        normText .= " Start ........ Enter`n"
        normText .= " Select ....... Escape`n"
        normText .= " ────────────────────────`n"
        normText .= " L3 ........... Sniper Mode`n"
        normText .= " R3 ........... Rapid Scroll`n"
        normText .= " PS ........... Pause/Resume"

        HUD.gui.AddText("cWhite ys", normText)

        HUD.gui.Show("NoActivate x-9999 y-9999")
        WinSetTransparent(200, HUD.gui.Hwnd)
        WinGetPos(,, &w, &h, HUD.gui.Hwnd)
        MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
        HUD.xPos := mL + 20
        HUD.yPos := mB - h - 20
        HUD.gui.Hide()
    }

    static Show() {
        if HUD.visible
            return
        HUD.gui.Show("NoActivate x" HUD.xPos " y" HUD.yPos)
        HUD.visible := true
    }

    static Hide() {
        if !HUD.visible
            return
        HUD.gui.Hide()
        HUD.visible := false
    }
}

; ============================================================
;  Recording Overlay — GDI+ rendered voice indicator
; ============================================================
class RecordingOverlay {
    static hwnd := 0
    static visible := false
    static animTimer := 0
    static animFrame := 0
    static barPhases := []
    static W := 280
    static H := 50
    static audioLevel := 0.0
    static smoothLevel := 0.0
    static isTranscribing := false
    static posX := 0
    static posY := 0
    ; GDI+ cached handles
    static gdipToken := 0
    static screenDC := 0
    static memDC := 0
    static hBmp := 0
    static oldBmp := 0
    ; Pre-cached GDI+ objects (created once in Init, reused every frame)
    static pillBrush := 0
    static pillPath := 0
    static barBrushes := []      ; 9 bar brushes
    static dotBrushes := []      ; 3 transcribing dot base brushes
    static pGraphics := 0        ; Cached graphics context
    ; Pre-cached buffers for UpdateLayeredWindow (allocated once)
    static ptSrc := 0
    static ptDst := 0
    static szBuf := 0
    static bfBuf := 0
    ; Pre-computed sin lookup table (628 entries ≈ 0..2π in 0.01 steps)
    static sinTable := []
    ; Cached level file path
    static levelFile := ""
    ; Pre-computed bar layout constants
    static barW := 6.0
    static barGap := 4.0
    static barStartX := 0.0
    static barMaxH := 0.0
    static barMinH := 6.0
    ; Cached bar X positions
    static barXPositions := []

    static Init() {
        ; Start GDI+
        si := Buffer(24, 0)
        NumPut("UInt", 1, si, 0)
        token := 0
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0)
        RecordingOverlay.gdipToken := token

        W := RecordingOverlay.W
        H := RecordingOverlay.H

        ; Create layered window
        exStyle := 0x80000 | 0x8 | 0x80 | 0x20 | 0x08000000
        RecordingOverlay.hwnd := DllCall("CreateWindowEx"
            , "UInt", exStyle
            , "Str", "Static"
            , "Str", ""
            , "UInt", 0x80000000
            , "Int", 0, "Int", 0
            , "Int", W, "Int", H
            , "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")

        ; Pre-calc position
        MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
        RecordingOverlay.posX := mL + (mR - mL - W) // 2
        RecordingOverlay.posY := mB - H - 80

        ; Pre-create cached DC and bitmap
        RecordingOverlay.screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
        RecordingOverlay.memDC := DllCall("CreateCompatibleDC", "Ptr", RecordingOverlay.screenDC, "Ptr")
        RecordingOverlay.hBmp := DllCall("CreateCompatibleBitmap", "Ptr", RecordingOverlay.screenDC, "Int", W, "Int", H, "Ptr")
        RecordingOverlay.oldBmp := DllCall("SelectObject", "Ptr", RecordingOverlay.memDC, "Ptr", RecordingOverlay.hBmp, "Ptr")

        ; Create persistent Graphics from the cached DC
        pg := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", RecordingOverlay.memDC, "Ptr*", &pg)
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pg, "Int", 4)
        RecordingOverlay.pGraphics := pg

        ; Pre-build pill path (static shape, never changes)
        pPath := 0
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &pPath)
        r := H / 2.0
        DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath, "Float", 0.0, "Float", 0.0, "Float", Float(r * 2), "Float", Float(H), "Float", 90.0, "Float", 180.0)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath, "Float", Float(W - r * 2), "Float", 0.0, "Float", Float(r * 2), "Float", Float(H), "Float", 270.0, "Float", 180.0)
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", pPath)
        RecordingOverlay.pillPath := pPath

        ; Pre-create pill background brush
        pb := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xD01a1a2e, "Ptr*", &pb)
        RecordingOverlay.pillBrush := pb

        ; Pre-create 9 bar brushes (colors never change)
        barColors := [0xFF4FC3F7, 0xFF4DD0E1, 0xFF4DB6AC, 0xFF66BB6A, 0xFF81C784
                    , 0xFF66BB6A, 0xFF4DB6AC, 0xFF4DD0E1, 0xFF4FC3F7]
        RecordingOverlay.barBrushes := []
        for clr in barColors {
            bb := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", clr, "Ptr*", &bb)
            RecordingOverlay.barBrushes.Push(bb)
        }

        ; Pre-create 3 transcribing dot brushes (base colors, alpha updated per frame)
        dotColors := [0xFF4FC3F7, 0xFF4DD0E1, 0xFF4DB6AC]
        RecordingOverlay.dotBrushes := []
        for clr in dotColors {
            db := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", clr, "Ptr*", &db)
            RecordingOverlay.dotBrushes.Push(db)
        }

        ; Pre-compute bar layout
        bw := RecordingOverlay.barW
        bg := RecordingOverlay.barGap
        totalBarsW := 9 * bw + 8 * bg
        RecordingOverlay.barStartX := (W - totalBarsW) / 2 + 10
        RecordingOverlay.barMaxH := H - 14.0
        RecordingOverlay.barXPositions := []
        loop 9
            RecordingOverlay.barXPositions.Push(RecordingOverlay.barStartX + (A_Index - 1) * (bw + bg))

        ; Pre-compute sin lookup table (0..627 → sin(0.00..6.27))
        RecordingOverlay.sinTable := []
        loop 628
            RecordingOverlay.sinTable.Push(Sin((A_Index - 1) * 0.01))

        ; Pre-allocate UpdateLayeredWindow buffers
        RecordingOverlay.ptSrc := Buffer(8, 0)
        RecordingOverlay.ptDst := Buffer(8, 0)
        NumPut("Int", RecordingOverlay.posX, RecordingOverlay.ptDst, 0)
        NumPut("Int", RecordingOverlay.posY, RecordingOverlay.ptDst, 4)
        RecordingOverlay.szBuf := Buffer(8, 0)
        NumPut("Int", W, RecordingOverlay.szBuf, 0)
        NumPut("Int", H, RecordingOverlay.szBuf, 4)
        RecordingOverlay.bfBuf := Buffer(4, 0)
        NumPut("UChar", 0, RecordingOverlay.bfBuf, 0)
        NumPut("UChar", 0, RecordingOverlay.bfBuf, 1)
        NumPut("UChar", 255, RecordingOverlay.bfBuf, 2)
        NumPut("UChar", 1, RecordingOverlay.bfBuf, 3)

        ; Init random bar phases
        RecordingOverlay.barPhases := []
        loop 9
            RecordingOverlay.barPhases.Push(Random(0, 628) / 100)

        ; Cache level file path
        RecordingOverlay.levelFile := A_ScriptDir "\whisper_level.txt"

        ; Pre-bind timer callback once
        RecordingOverlay.animTimer := ObjBindMethod(RecordingOverlay, "_Animate")
    }

    static Show() {
        if RecordingOverlay.visible
            return
        RecordingOverlay.visible := true
        RecordingOverlay.isTranscribing := false
        RecordingOverlay.animFrame := 0
        RecordingOverlay.smoothLevel := 0.0

        DllCall("SetWindowPos", "Ptr", RecordingOverlay.hwnd
            , "Ptr", -1
            , "Int", RecordingOverlay.posX
            , "Int", RecordingOverlay.posY
            , "Int", RecordingOverlay.W
            , "Int", RecordingOverlay.H
            , "UInt", 0x0040 | 0x0010)
        DllCall("ShowWindow", "Ptr", RecordingOverlay.hwnd, "Int", 8)

        SetTimer(RecordingOverlay.animTimer, 66)
    }

    static Hide() {
        if !RecordingOverlay.visible
            return
        RecordingOverlay.visible := false
        SetTimer(RecordingOverlay.animTimer, 0)
        DllCall("ShowWindow", "Ptr", RecordingOverlay.hwnd, "Int", 0)
    }

    static ShowTranscribing() {
        RecordingOverlay.isTranscribing := true
        RecordingOverlay.animFrame := 0
        if !RecordingOverlay.visible {
            RecordingOverlay.visible := true
            DllCall("SetWindowPos", "Ptr", RecordingOverlay.hwnd
                , "Ptr", -1
                , "Int", RecordingOverlay.posX
                , "Int", RecordingOverlay.posY
                , "Int", RecordingOverlay.W
                , "Int", RecordingOverlay.H
                , "UInt", 0x0040 | 0x0010)
            DllCall("ShowWindow", "Ptr", RecordingOverlay.hwnd, "Int", 8)
        }
        SetTimer(RecordingOverlay.animTimer, 66)
    }

    static _SinLookup(val) {
        ; Fast sin approximation via lookup table
        ; Normalize val to 0..6.28 range
        val := Mod(val, 6.28318)
        if (val < 0)
            val += 6.28318
        idx := Integer(val * 100) + 1
        if (idx > 628)
            idx := 628
        if (idx < 1)
            idx := 1
        return RecordingOverlay.sinTable[idx]
    }

    static _Animate() {
        if !RecordingOverlay.visible
            return
        RecordingOverlay.animFrame += 1
        pg := RecordingOverlay.pGraphics

        ; Clear and draw pill background (cached path + brush)
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", pg, "UInt", 0)
        DllCall("gdiplus\GdipFillPath", "Ptr", pg, "Ptr", RecordingOverlay.pillBrush, "Ptr", RecordingOverlay.pillPath)

        if RecordingOverlay.isTranscribing
            RecordingOverlay._DrawTranscribing(pg)
        else
            RecordingOverlay._DrawRecording(pg)

        ; UpdateLayeredWindow (all buffers pre-allocated)
        DllCall("UpdateLayeredWindow"
            , "Ptr", RecordingOverlay.hwnd
            , "Ptr", RecordingOverlay.screenDC
            , "Ptr", RecordingOverlay.ptDst
            , "Ptr", RecordingOverlay.szBuf
            , "Ptr", RecordingOverlay.memDC
            , "Ptr", RecordingOverlay.ptSrc
            , "UInt", 0
            , "Ptr", RecordingOverlay.bfBuf
            , "UInt", 2)
    }

    static _DrawRecording(pg) {
        frame := RecordingOverlay.animFrame
        H := RecordingOverlay.H

        ; Read audio level from file
        try {
            raw := FileRead(RecordingOverlay.levelFile)
            RecordingOverlay.audioLevel := Number(Trim(raw))
        } catch {
            RecordingOverlay.audioLevel := 0.0
        }

        ; Smooth the level
        target := RecordingOverlay.audioLevel
        current := RecordingOverlay.smoothLevel
        RecordingOverlay.smoothLevel := (target > current)
            ? current + (target - current) * 0.5
            : current + (target - current) * 0.15
        level := RecordingOverlay.smoothLevel

        ; Pulsing red recording dot (use sin lookup)
        pulse := 0.7 + RecordingOverlay._SinLookup(frame * 0.1) * 0.3
        dotAlpha := Floor(255 * pulse)
        ; Create dot brush inline (alpha changes each frame, can't cache)
        dotBrush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", (dotAlpha << 24) | 0xFF4444, "Ptr*", &dotBrush)
        DllCall("gdiplus\GdipFillEllipse", "Ptr", pg, "Ptr", dotBrush
            , "Float", 18.0, "Float", Float((H - 12.0) / 2), "Float", 12.0, "Float", 12.0)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", dotBrush)

        ; Sound bars — 9 bars using pre-cached brushes and positions
        ; Draw as simple rounded rects (FillEllipse for caps + FillRectangle for body)
        bw := RecordingOverlay.barW
        minH := RecordingOverlay.barMinH
        maxH := RecordingOverlay.barMaxH

        loop 9 {
            phase := RecordingOverlay.barPhases[A_Index]
            wave := RecordingOverlay._SinLookup(frame * 0.08 + phase) * 0.4
                  + RecordingOverlay._SinLookup(frame * 0.13 + phase * 1.7) * 0.2
            barLevel := level * (0.5 + wave)
            barLevel := Min(Max(barLevel, 0.05), 1.0)
            barH := minH + barLevel * (maxH - minH)

            x := RecordingOverlay.barXPositions[A_Index]
            y := (H - barH) / 2
            brush := RecordingOverlay.barBrushes[A_Index]

            ; Draw bar as: top cap (ellipse) + body (rect) + bottom cap (ellipse)
            ; This avoids creating/destroying a GdipPath every frame
            halfW := bw / 2.0
            if (barH > bw) {
                ; Top cap
                DllCall("gdiplus\GdipFillEllipse", "Ptr", pg, "Ptr", brush
                    , "Float", x, "Float", y, "Float", bw, "Float", bw)
                ; Body
                DllCall("gdiplus\GdipFillRectangle", "Ptr", pg, "Ptr", brush
                    , "Float", x, "Float", y + halfW, "Float", bw, "Float", barH - bw)
                ; Bottom cap
                DllCall("gdiplus\GdipFillEllipse", "Ptr", pg, "Ptr", brush
                    , "Float", x, "Float", y + barH - bw, "Float", bw, "Float", bw)
            } else {
                ; Very short bar — just draw an ellipse
                DllCall("gdiplus\GdipFillEllipse", "Ptr", pg, "Ptr", brush
                    , "Float", x, "Float", y, "Float", bw, "Float", barH)
            }
        }
    }

    static _DrawTranscribing(pg) {
        frame := RecordingOverlay.animFrame
        W := RecordingOverlay.W
        H := RecordingOverlay.H
        dotSize := 10.0
        dotGap := 20.0
        totalW := 3 * dotSize + 2 * dotGap
        startX := (W - totalW) / 2

        loop 3 {
            phase := (A_Index - 1) * 0.8
            scale := 0.5 + RecordingOverlay._SinLookup(frame * 0.12 - phase) * 0.5
            scale := Max(scale, 0.2)
            alpha := Floor(100 + scale * 155)
            sz := dotSize * (0.6 + scale * 0.4)

            x := startX + (A_Index - 1) * (dotSize + dotGap) + (dotSize - sz) / 2
            y := (H - sz) / 2

            ; Update dot brush alpha
            baseBrush := RecordingOverlay.dotBrushes[A_Index]
            ; Need to create temp brush with correct alpha (can't change alpha on existing)
            dotBrush := 0
            baseColors := [0x4FC3F7, 0x4DD0E1, 0x4DB6AC]
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", (alpha << 24) | baseColors[A_Index], "Ptr*", &dotBrush)
            DllCall("gdiplus\GdipFillEllipse", "Ptr", pg, "Ptr", dotBrush
                , "Float", x, "Float", y, "Float", sz, "Float", sz)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", dotBrush)
        }
    }
}

; ============================================================
;  XInput via DLL
; ============================================================
class XI {
    static hModule := 0
    static pGetState := 0
    static _buf := Buffer(16, 0)  ; Pre-allocated, reused every poll
    ; Cached result object — avoids creating a new object each frame
    static _result := {connected: false, buttons: 0, lt: 0, rt: 0, lx: 0, ly: 0, rx: 0, ry: 0}

    static Init() {
        for dll in ["xinput1_4", "xinput1_3", "xinput9_1_0"] {
            XI.hModule := DllCall("LoadLibrary", "Str", dll, "Ptr")
            if XI.hModule
                break
        }
        if !XI.hModule {
            MsgBox("Could not load XInput DLL!", "DS3Mouse — Error")
            ExitApp()
        }
        XI.pGetState := DllCall("GetProcAddress", "Ptr", XI.hModule, "AStr", "XInputGetState", "Ptr")
        if !XI.pGetState {
            MsgBox("Could not find XInputGetState!", "DS3Mouse — Error")
            ExitApp()
        }
    }

    static GetState(userIndex := 0) {
        r := DllCall(XI.pGetState, "UInt", userIndex, "Ptr", XI._buf, "UInt")
        o := XI._result
        if (r != 0) {
            o.connected := false
            o.buttons := 0
            o.lt := 0
            o.rt := 0
            o.lx := 0
            o.ly := 0
            o.rx := 0
            o.ry := 0
        } else {
            o.connected := true
            o.buttons := NumGet(XI._buf, 4, "UShort")
            o.lt      := NumGet(XI._buf, 6, "UChar")
            o.rt      := NumGet(XI._buf, 7, "UChar")
            o.lx      := NumGet(XI._buf, 8, "Short")
            o.ly      := NumGet(XI._buf, 10, "Short")
            o.rx      := NumGet(XI._buf, 12, "Short")
            o.ry      := NumGet(XI._buf, 14, "Short")
        }
        return o
    }
}

class XINPUT {
    static DPAD_UP        := 0x0001
    static DPAD_DOWN      := 0x0002
    static DPAD_LEFT      := 0x0004
    static DPAD_RIGHT     := 0x0008
    static START          := 0x0010
    static BACK           := 0x0020
    static LEFT_THUMB     := 0x0040
    static RIGHT_THUMB    := 0x0080
    static LEFT_SHOULDER  := 0x0100
    static RIGHT_SHOULDER := 0x0200
    static GUIDE          := 0x0400
    static A              := 0x1000
    static B              := 0x2000
    static X              := 0x4000
    static Y              := 0x8000
}

; ============================================================
;  Whisper TCP client
; ============================================================
class Whisper {
    static pid := 0
    static sock := 0
    static connected := false

    static LaunchServer() {
        pythonScript := A_ScriptDir "\whisper_server.py"
        if !FileExist(pythonScript) {
            MsgBox("whisper_server.py not found in " A_ScriptDir, "DS3Mouse — Error")
            return false
        }

        ToolTip("Loading Whisper model...`nThis may take a moment on first run.")

        ; Launch Python server hidden
        Run('pythonw "' pythonScript '"',, "Hide", &pid)
        Whisper.pid := pid

        ; Wait for server to be ready (try connecting for up to 120 seconds)
        startTime := A_TickCount
        loop {
            if (A_TickCount - startTime > 120000) {
                ToolTip()
                MsgBox("Whisper server failed to start within 120 seconds.", "DS3Mouse — Error")
                return false
            }
            try {
                Whisper.sock := Whisper._Connect()
                if Whisper.sock {
                    ; Read READY message
                    resp := Whisper._ReadLine()
                    if (resp = "READY") {
                        Whisper.connected := true
                        ToolTip("Whisper model loaded!")
                        SetTimer(() => ToolTip(), -2000)
                        return true
                    }
                    Whisper._Close()
                }
            }
            Sleep(1000)
        }
    }

    static _Connect() {
        sock := DllCall("Ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
        if (sock = -1)
            return 0

        ; Build sockaddr_in
        addr := Buffer(16, 0)
        NumPut("UShort", 2, addr, 0)                    ; AF_INET
        NumPut("UShort", Whisper._Htons(Config.WhisperPort), addr, 2)

        ; Convert IP to integer
        parts := StrSplit(Config.WhisperHost, ".")
        ip := (Integer(parts[1]) | Integer(parts[2]) << 8 | Integer(parts[3]) << 16 | Integer(parts[4]) << 24)
        NumPut("UInt", ip, addr, 4)

        result := DllCall("Ws2_32\connect", "Ptr", sock, "Ptr", addr, "Int", 16, "Int")
        if (result != 0) {
            DllCall("Ws2_32\closesocket", "Ptr", sock)
            return 0
        }
        return sock
    }

    static _Htons(val) {
        return ((val & 0xFF) << 8) | ((val >> 8) & 0xFF)
    }

    static _Send(text) {
        if !Whisper.sock
            return
        buf := Buffer(StrPut(text, "UTF-8") - 1)
        StrPut(text, buf, "UTF-8")
        DllCall("Ws2_32\send", "Ptr", Whisper.sock, "Ptr", buf, "Int", buf.Size, "Int", 0, "Int")
    }

    static _ReadLine(timeout := 10000) {
        if !Whisper.sock
            return ""

        ; Set receive timeout
        tv := Buffer(4)
        NumPut("UInt", timeout, tv, 0)
        DllCall("Ws2_32\setsockopt", "Ptr", Whisper.sock, "Int", 0xFFFF, "Int", 0x1006, "Ptr", tv, "Int", 4)

        result := ""
        buf := Buffer(1)
        loop {
            n := DllCall("Ws2_32\recv", "Ptr", Whisper.sock, "Ptr", buf, "Int", 1, "Int", 0, "Int")
            if (n <= 0)
                break
            ch := Chr(NumGet(buf, 0, "UChar"))
            if (ch = "`n")
                break
            result .= ch
        }
        return result
    }

    static _Close() {
        if Whisper.sock {
            DllCall("Ws2_32\closesocket", "Ptr", Whisper.sock)
            Whisper.sock := 0
        }
        Whisper.connected := false
    }

    static StartRecording() {
        if !Whisper.connected {
            ; Try to reconnect
            try {
                Whisper.sock := Whisper._Connect()
                if Whisper.sock {
                    resp := Whisper._ReadLine(3000)
                    if (resp = "READY")
                        Whisper.connected := true
                    else {
                        Whisper._Close()
                        return
                    }
                }
            }
        }
        if !Whisper.connected
            return
        Whisper._Send("START`n")
        Whisper._ReadLine(3000)  ; Read OK response
    }

    static StopAndGetText() {
        if !Whisper.connected
            return ""
        Whisper._Send("STOP`n")
        ; Wait for transcription (can take a while)
        resp := Whisper._ReadLine(30000)
        if (SubStr(resp, 1, 5) = "TEXT:")
            return SubStr(resp, 6)
        return ""
    }

    static Shutdown() {
        try Whisper._Send("QUIT`n")
        Whisper._Close()
        if Whisper.pid {
            try ProcessClose(Whisper.pid)
            Whisper.pid := 0
        }
    }
}

; Initialize Winsock
DllCall("Ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", Buffer(400, 0), "Int")

; ============================================================
;  Startup
; ============================================================
XI.Init()

testState := XI.GetState(Config.UserIndex)
if !testState.connected {
    MsgBox("No XInput controller found on index " Config.UserIndex "!", "DS3Mouse — Error")
    ExitApp()
}

HUD.Init()
RecordingOverlay.Init()

try TraySetIcon(A_ScriptDir "\DS3Mouse.ico")
A_IconTip := "DS3Mouse — Active (XInput " Config.UserIndex ")"

; Disable default tray menu (prevents script from pausing on right-click)
A_TrayMenu.Delete()
A_TrayMenu.Add("DS3Mouse", (*) => 0)
A_TrayMenu.Disable("DS3Mouse")
A_TrayMenu.Add()
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => (Whisper.Shutdown(), ExitApp()))
ToolTip("DS3Mouse started (XInput)`nController index: " Config.UserIndex "`nLoading Whisper...")

; Launch Whisper server
Whisper.LaunchServer()

; Clean up on exit
OnExit((*) => Whisper.Shutdown())

SetTimer(MainLoop, Config.PollRate)

; ============================================================
;  Main loop
; ============================================================
MainLoop() {
    gp := XI.GetState(Config.UserIndex)
    if !gp.connected
        return

    ; ── Guide/PS button toggle (works even when paused) ──
    guideNow := (gp.buttons & XINPUT.GUIDE) != 0
    if (guideNow && !State.PrevGuide) {
        State.Active := !State.Active
        ToolTip(State.Active ? "DS3Mouse ACTIVE" : "DS3Mouse PAUSED")
        SetTimer(() => ToolTip(), -2000)
        if !State.Active {
            HUD.Hide()
            if State.L2Down {
                Click("Right Up")
                State.L2Down := false
            }
            if State.R2Down {
                Click("Up")
                State.R2Down := false
            }
            if State.CrossDown {
                Click("Up")
                State.CrossDown := false
            }
        }
    }
    State.PrevGuide := guideNow

    if !State.Active
        return

    ; ── L1 held? Show/hide HUD ──
    l1Held := (gp.buttons & XINPUT.LEFT_SHOULDER) != 0
    if (l1Held && !State.PrevL1)
        HUD.Show()
    else if (!l1Held && State.PrevL1)
        HUD.Hide()
    State.PrevL1 := l1Held

    ; ── LEFT STICK → Cursor ──
    MoveCursor(gp.lx, gp.ly)

    ; ── RIGHT STICK → Scroll ──
    HandleStickScroll(gp.rx, gp.ry)

    ; ── TRIGGERS → Click ──
    HandleTriggers(gp.lt, gp.rt)

    ; ── D-PAD (only real d-pad presses, ignore if left stick is active) ──
    ; XInput leaks stick input into d-pad bits — suppress d-pad when ANY stick movement detected
    ; Use a very low threshold: if the stick has moved at all from center, block d-pad
    stickMagSq := gp.lx * gp.lx + gp.ly * gp.ly
    if (stickMagSq < 1000000)  ; ~1000 magnitude — barely touching the stick
        HandleDPad(gp.buttons, l1Held)
    else {
        ; Mask out d-pad bits entirely when stick is active
        State.LastDpad := 0
        State.DpadRepeating := false
        State.DpadReleaseCount := 0
        State.DpadConfirmedRelease := false
    }

    ; ── Face buttons + shoulders ──
    HandleButtons(gp.buttons, l1Held)

    State.PrevButtons := gp.buttons
}

; ============================================================
;  Helpers
; ============================================================
BtnPressed(current, mask) {
    return (current & mask) != 0 && (State.PrevButtons & mask) = 0
}

BtnHeld(current, mask) {
    return (current & mask) != 0
}

; ============================================================
;  Cursor movement — left stick (radial deadzone)
; ============================================================
MoveCursor(lx, ly) {
    ly := -ly
    dz := Config.CursorDeadzone * 1.0

    ; Fast squared check avoids Sqrt when inside deadzone (most frames)
    magSq := lx * lx + ly * ly
    dzSq := dz * dz
    if (magSq < dzSq) {
        State.MoveAccumX := 0.0
        State.MoveAccumY := 0.0
        return
    }
    magnitude := Sqrt(magSq)

    dirX := lx / magnitude
    dirY := ly / magnitude
    normalized := (magnitude - dz) / (32767.0 - dz)
    if (normalized > 1.0)
        normalized := 1.0

    curved := normalized ** Config.CursorExponent

    minSpd := Config.CursorMinSpeed
    maxSpd := Config.CursorMaxSpeed * 1.0
    if State.Sniper {
        minSpd := minSpd / Config.SniperDivisor
        maxSpd := maxSpd / Config.SniperDivisor
    }

    speed := minSpd + (maxSpd - minSpd) * curved

    State.MoveAccumX += dirX * speed * curved
    State.MoveAccumY += dirY * speed * curved

    ix := Integer(State.MoveAccumX)
    iy := Integer(State.MoveAccumY)

    if (ix != 0 || iy != 0) {
        MouseMove(ix, iy, 0, "R")
        State.MoveAccumX -= ix
        State.MoveAccumY -= iy
    }
}

ApplyStickCurve(val, deadzone, exponent) {
    sign := (val >= 0) ? 1.0 : -1.0
    mag := Abs(val) * 1.0
    if (mag < deadzone)
        return 0.0
    normalized := (mag - deadzone) / (32767.0 - deadzone)
    if (normalized > 1.0)
        normalized := 1.0
    return sign * (normalized ** exponent)
}

; ============================================================
;  Right stick → scroll
; ============================================================
HandleStickScroll(rx, ry) {
    ry := -ry
    dz := Config.ScrollDeadzone

    if (Abs(ry) >= dz) {
        ny := ApplyStickCurve(ry, dz, Config.ScrollExponent)
        minSpd := Config.ScrollMinSpeed
        maxSpd := Config.ScrollMaxSpeed
        if State.RapidScroll {
            minSpd *= 3
            maxSpd *= 3
        }
        speed := minSpd + (maxSpd - minSpd) * Abs(ny)
        State.ScrollAccumV += ny * speed

        lines := Integer(State.ScrollAccumV)
        if (lines != 0) {
            if (lines > 0)
                Click("WheelDown " Abs(lines))
            else
                Click("WheelUp " Abs(lines))
            State.ScrollAccumV -= lines
        }
    } else {
        State.ScrollAccumV := 0.0
    }

    if (Abs(rx) >= dz) {
        nx := ApplyStickCurve(rx, dz, Config.ScrollExponent)
        speed := Config.ScrollMinSpeed + (Config.ScrollMaxSpeed - Config.ScrollMinSpeed) * Abs(nx)
        State.ScrollAccumH += nx * speed

        cols := Integer(State.ScrollAccumH)
        if (cols != 0) {
            if (cols > 0)
                Click("WheelRight " Abs(cols))
            else
                Click("WheelLeft " Abs(cols))
            State.ScrollAccumH -= cols
        }
    } else {
        State.ScrollAccumH := 0.0
    }
}

; ============================================================
;  Triggers
; ============================================================
HandleTriggers(lt, rt) {
    thresh := Config.TriggerThreshold

    l2Now := (lt >= thresh)
    if (l2Now && !State.L2Down) {
        Click("Right Down")
        State.L2Down := true
    } else if (!l2Now && State.L2Down) {
        Click("Right Up")
        State.L2Down := false
    }

    r2Now := (rt >= thresh)
    if (r2Now && !State.R2Down) {
        Click("Down")
        State.R2Down := true
    } else if (!r2Now && State.R2Down) {
        Click("Up")
        State.R2Down := false
    }
}

; ============================================================
;  D-Pad
; ============================================================
HandleDPad(buttons, l1Held) {
    dpad := buttons & 0x000F

    ; Track confirmed release — d-pad must be released for 6+ consecutive
    ; polls (~30ms) before a new press is accepted. This prevents false
    ; double-triggers from noisy XInput reports.
    if (dpad = 0) {
        State.DpadReleaseCount += 1
        if (State.DpadReleaseCount >= 6) {
            State.DpadConfirmedRelease := true
        }
        State.LastDpad := 0
        State.DpadRepeating := false
        State.DpadScrollTick := 0
        return
    }

    ; New press — only accept if release was confirmed
    if (dpad != State.LastDpad) {
        if (State.DpadConfirmedRelease) {
            State.LastDpad := dpad
            State.DpadScrollTick := 0
            State.DpadRepeating := false
            State.DpadReleaseCount := 0
            State.DpadConfirmedRelease := false
            DPadAction(dpad, l1Held)
        }
        return
    }

    ; Same direction held — handle repeat
    State.DpadScrollTick += Config.PollRate
    threshold := State.DpadRepeating ? Config.DpadRepeatInterval : Config.DpadRepeatDelay
    if (State.DpadScrollTick >= threshold) {
        State.DpadScrollTick := 0
        State.DpadRepeating := true
        DPadAction(dpad, l1Held)
    }
}

DPadAction(dpad, l1Held) {
    if l1Held {
        if (dpad & XINPUT.DPAD_UP)
            Send("{PgUp}")
        if (dpad & XINPUT.DPAD_DOWN)
            Send("{PgDn}")
        if (dpad & XINPUT.DPAD_LEFT)
            Send("{Home}")
        if (dpad & XINPUT.DPAD_RIGHT)
            Send("{End}")
    } else {
        if (dpad & XINPUT.DPAD_UP)
            Send("{Up}")
        if (dpad & XINPUT.DPAD_DOWN)
            Send("{Down}")
        if (dpad & XINPUT.DPAD_LEFT)
            Send("{Left}")
        if (dpad & XINPUT.DPAD_RIGHT)
            Send("{Right}")
    }
}

; ============================================================
;  Face buttons + shoulders
; ============================================================
HandleButtons(buttons, l1Held) {
    ; A / Cross — hold for drag, or Enter with L1
    crossNow := BtnHeld(buttons, XINPUT.A)
    if l1Held {
        if BtnPressed(buttons, XINPUT.A)
            Send("{Enter}")
    } else {
        if (crossNow && !State.CrossDown) {
            Click("Down")
            State.CrossDown := true
        } else if (!crossNow && State.CrossDown) {
            Click("Up")
            State.CrossDown := false
        }
    }

    ; B / Circle
    if BtnPressed(buttons, XINPUT.B) {
        if l1Held
            Send("{Escape}")
        else
            Click("Right")
    }

    ; X / Square — hold to repeat Backspace, or Clear All with L1
    sqNow := BtnHeld(buttons, XINPUT.X)
    if l1Held {
        if BtnPressed(buttons, XINPUT.X)
            Send("^a{Delete}")
    } else {
        if (sqNow && !State.SquareHeld) {
            Send("{Backspace}")
            State.SquareHeld := true
            State.SquareRepeatTick := 0
        } else if (sqNow && State.SquareHeld) {
            State.SquareRepeatTick += Config.PollRate
            if (State.SquareRepeatTick >= 30) {
                State.SquareRepeatTick := 0
                Send("{Backspace}")
            }
        } else if !sqNow {
            State.SquareHeld := false
            State.SquareRepeatTick := 0
        }
    }

    ; Y / Triangle — toggles between Copy and Paste (Tab with L1)
    if BtnPressed(buttons, XINPUT.Y) {
        if l1Held {
            Send("{Tab}")
        } else {
            if State.TriangleNextPaste {
                Send("^v")
                State.TriangleNextPaste := false
            } else {
                Send("^c")
                State.TriangleNextPaste := true
            }
        }
    }

    ; R1 — hold to dictate (local Whisper), or middle click with L1
    r1Now := BtnHeld(buttons, XINPUT.RIGHT_SHOULDER)
    if l1Held {
        if BtnPressed(buttons, XINPUT.RIGHT_SHOULDER)
            Click("Middle")
    } else {
        if (r1Now && !State.R1Dictating && !State.WaitingForTranscription) {
            ; Delete old result file
            resultFile := A_ScriptDir "\whisper_result.txt"
            if FileExist(resultFile)
                FileDelete(resultFile)
            Whisper.StartRecording()
            State.R1Dictating := true
            RecordingOverlay.Show()
        } else if (!r1Now && State.R1Dictating) {
            State.R1Dictating := false
            RecordingOverlay.ShowTranscribing()
            ; Send STOP (non-blocking, don't wait for response)
            Whisper._Send("STOP`n")
            ; Start polling for result file
            State.WaitingForTranscription := true
            SetTimer(PollTranscriptionResult, 100)
        }
    }

    ; Start → Enter
    if BtnPressed(buttons, XINPUT.START)
        Send("{Enter}")

    ; Back/Select → Escape
    if BtnPressed(buttons, XINPUT.BACK)
        Send("{Escape}")

    ; L3 → toggle sniper
    l3Now := BtnHeld(buttons, XINPUT.LEFT_THUMB)
    if (l3Now && !State.PrevL3) {
        State.Sniper := !State.Sniper
        ToolTip(State.Sniper ? "Sniper mode ON" : "Sniper mode OFF")
        SetTimer(() => ToolTip(), -1500)
    }
    State.PrevL3 := l3Now

    ; R3 → toggle rapid scroll
    r3Now := BtnHeld(buttons, XINPUT.RIGHT_THUMB)
    if (r3Now && !State.PrevR3) {
        State.RapidScroll := !State.RapidScroll
        ToolTip(State.RapidScroll ? "Rapid scroll ON" : "Rapid scroll OFF")
        SetTimer(() => ToolTip(), -1500)
    }
    State.PrevR3 := r3Now
}

; ============================================================
;  Poll for transcription result file (non-blocking)
; ============================================================
PollTranscriptionResult() {
    resultFile := A_ScriptDir "\whisper_result.txt"

    if !FileExist(resultFile)
        return  ; Still transcribing, check again in 100ms

    ; Result file exists — read it
    SetTimer(PollTranscriptionResult, 0)  ; Stop polling
    State.WaitingForTranscription := false

    try {
        text := Trim(FileRead(resultFile, "UTF-8"))
        FileDelete(resultFile)
    } catch {
        text := ""
    }

    ; Drain the TCP response so the socket stays clean
    try Whisper._ReadLine(100)

    RecordingOverlay.Hide()

    if (text = "") {
        ToolTip("No speech detected")
        SetTimer(() => ToolTip(), -1500)
        return
    }

    ; Type the transcribed text
    SendText(text)

    ; Send Enter after delay
    SetTimer(() => Send("{Enter}"), -Config.DictateEnterDelay)
}
