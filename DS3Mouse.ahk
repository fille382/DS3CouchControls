#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Make DPI-aware so screen capture coordinates match actual pixels
DllCall("SetProcessDPIAware")

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
;    Start ................. Windows Start menu
;    Back / Select ......... Alt+Tab (D-pad to navigate, Cross=confirm, Circle=cancel)
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
    static GamePaused := false  ; Auto-paused due to game detection
    static Sniper := false
    static RapidScroll := false
    static L2Down := false
    static R2Down := false
    static MoveAccumX := 0.0
    static MoveAccumY := 0.0
    static ScrollAccumV := 0.0
    static ScrollAccumH := 0.0
    static DpadActive := false
    static DpadDirection := 0
    static DpadHeldMs := 0
    static DpadFired := false
    static DpadRepeating := false
    static DpadReleaseTime := 0
    static PrevButtons := 0
    static PrevL3 := false
    static PrevR3 := false
    static PrevGuide := false
    static PrevL1 := false
    static CrossDown := false
    static R1Dictating := false
    static WaitingForTranscription := false
    static R1IsVoiceCommand := false
    static TranscriptionStartTime := 0
    static SquareHeld := false
    static SquareRepeatTick := 0
    static TriangleNextPaste := false  ; false = next press copies, true = next press pastes
    static AltTabActive := false       ; Alt+Tab switcher is open
    static AltTabJustClosed := false   ; Block Cross click after Alt+Tab confirm
    static RadialVisible := false      ; Radial menu is showing
    static RadialSelected := -1        ; -1 = center/cancel, 0-7 = segment
    static RadialOriginX := 0          ; Cursor pos when menu opened
    static RadialOriginY := 0
}

; ============================================================
;  L1 overlay HUD — two pre-built windows, instant show/hide
; ============================================================
class HUD {
    static guiNormal := 0
    static guiVoice := 0
    static visible := false
    static mode := "normal"
    static normalPos := {x: 0, y: 0}
    static voicePos := {x: 0, y: 0}

    static _BuildGui(leftText, rightText) {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        g.BackColor := "0x1a1a2e"
        g.MarginX := 10
        g.MarginY := 8
        g.SetFont("s9", "Consolas")
        g.AddText("cWhite Section", leftText)
        g.AddText("cWhite ys", rightText)
        g.Show("NoActivate x-9999 y-9999")
        WinSetTransparent(200, g.Hwnd)
        WinGetPos(,, &w, &h, g.Hwnd)
        g.Hide()
        return {gui: g, w: w, h: h}
    }

    static Init() {
        ; Normal HUD
        nLeft := ""
        nLeft .= " L1 + MODIFIER LAYER`n"
        nLeft .= " ────────────────────────`n"
        nLeft .= " Cross ........ Enter`n"
        nLeft .= " Circle ....... Escape`n"
        nLeft .= " Square ....... Clear All`n"
        nLeft .= " Triangle ..... Tab`n"
        nLeft .= " ────────────────────────`n"
        nLeft .= " D-Up ......... Volume Up`n"
        nLeft .= " D-Down ....... Volume Down`n"
        nLeft .= " D-Left ....... Prev Track`n"
        nLeft .= " D-Right ...... Next Track`n"
        nLeft .= " R1 (hold) .... Voice Command"

        nRight := ""
        nRight .= " NORMAL CONTROLS`n"
        nRight .= " ────────────────────────`n"
        nRight .= " L-Stick ...... Mouse`n"
        nRight .= " R-Stick ...... Scroll`n"
        nRight .= " L2 ........... Right Click`n"
        nRight .= " R2 ........... Left Click`n"
        nRight .= " D-Pad ........ Arrow Keys`n"
        nRight .= " ────────────────────────`n"
        nRight .= " Cross ........ Left Click`n"
        nRight .= " Circle ....... Right Click`n"
        nRight .= " Square ....... Backspace`n"
        nRight .= " Triangle ..... Copy/Paste`n"
        nRight .= " R1 (hold) .... Dictate`n"
        nRight .= " Start ........ Start Menu`n"
        nRight .= " Select ....... Alt+Tab`n"
        nRight .= " ────────────────────────`n"
        nRight .= " L3 ........... Sniper Mode`n"
        nRight .= " R3 ........... Rapid Scroll`n"
        nRight .= " PS ........... Pause/Resume"

        n := HUD._BuildGui(nLeft, nRight)
        HUD.guiNormal := n.gui
        MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
        HUD.normalPos := {x: mL + 20, y: mB - n.h - 20}

        ; Voice command HUD
        vLeft := ""
        vLeft .= " VOICE COMMANDS (L1+R1)`n"
        vLeft .= " ─── EDITING ───────────────`n"
        vLeft .= " copy / paste / cut`n"
        vLeft .= " undo / redo`n"
        vLeft .= " select all / save / find`n"
        vLeft .= " ─── KEYS ─────────────────`n"
        vLeft .= " enter / escape / space`n"
        vLeft .= " backspace / delete / tab`n"
        vLeft .= " shift tab / home / end`n"
        vLeft .= " page up / page down`n"
        vLeft .= " up / down / left / right`n"
        vLeft .= " ─── MEDIA ────────────────`n"
        vLeft .= " play / pause / next`n"
        vLeft .= " previous / mute`n"
        vLeft .= " volume up / volume down"

        vRight := ""
        vRight .= " `n"
        vRight .= " ─── BROWSER ──────────────`n"
        vRight .= " new tab / close tab`n"
        vRight .= " reopen tab / next tab`n"
        vRight .= " previous tab / refresh`n"
        vRight .= " fullscreen / zoom in / out`n"
        vRight .= " ─── WINDOWS ──────────────`n"
        vRight .= " minimize / maximize`n"
        vRight .= " close window / desktop`n"
        vRight .= " screenshot / snip`n"
        vRight .= " lock / task manager`n"
        vRight .= " snap left / snap right`n"
        vRight .= " ─── APPS ─────────────────`n"
        vRight .= " spotify / browser`n"
        vRight .= " discord / explorer`n"
        vRight .= " settings / notepad / calc"

        v := HUD._BuildGui(vLeft, vRight)
        HUD.guiVoice := v.gui
        HUD.voicePos := {x: mL + 20, y: mB - v.h - 20}
    }

    static SetMode(newMode) {
        if (HUD.mode = newMode)
            return
        oldMode := HUD.mode
        HUD.mode := newMode
        if HUD.visible {
            ; Hide old, show new — instant swap
            if (oldMode = "normal")
                HUD.guiNormal.Hide()
            else
                HUD.guiVoice.Hide()
            if (newMode = "voice")
                HUD.guiVoice.Show("NoActivate x" HUD.voicePos.x " y" HUD.voicePos.y)
            else
                HUD.guiNormal.Show("NoActivate x" HUD.normalPos.x " y" HUD.normalPos.y)
        }
    }

    static Show() {
        if HUD.visible
            return
        if (HUD.mode = "voice")
            HUD.guiVoice.Show("NoActivate x" HUD.voicePos.x " y" HUD.voicePos.y)
        else
            HUD.guiNormal.Show("NoActivate x" HUD.normalPos.x " y" HUD.normalPos.y)
        HUD.visible := true
    }

    static Hide() {
        if !HUD.visible
            return
        HUD.guiNormal.Hide()
        HUD.guiVoice.Hide()
        HUD.visible := false
    }
}


; ============================================================
;  Clipboard Toast — simple ToolTip showing copied text
; ============================================================
class ClipboardToast {
    static Show() {
        clipText := A_Clipboard
        if (clipText = "")
            clipText := "(empty)"
        if (StrLen(clipText) > 100)
            clipText := SubStr(clipText, 1, 97) "..."
        clipText := StrReplace(clipText, "`r`n", " ")
        clipText := StrReplace(clipText, "`n", " ")
        ToolTip("Copied: " clipText)
        SetTimer(() => ToolTip(), -4000)
    }

    static Hide() {
        ToolTip()
    }

    static Init() {
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
;  Zoom Lens — custom magnifier using GDI BitBlt/StretchBlt
; ============================================================
class ZoomLens {
    static active := false
    static gui := 0
    static timer := 0
    static screenDC := 0
    static memDC := 0
    static hBmp := 0
    static oldBmp := 0
    static LensSize := 700
    static ZoomFactor := 2.5
    static CaptureSize := 0

    static Init() {
        ZoomLens.CaptureSize := Integer(ZoomLens.LensSize / ZoomLens.ZoomFactor)

        ZoomLens.gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        ZoomLens.gui.BackColor := "000000"
        ZoomLens.gui.Show("NoActivate Hide x0 y0 w" ZoomLens.LensSize " h" ZoomLens.LensSize)
        hRgn := DllCall("CreateEllipticRgn", "Int", 0, "Int", 0
            , "Int", ZoomLens.LensSize, "Int", ZoomLens.LensSize, "Ptr")
        DllCall("SetWindowRgn", "Ptr", ZoomLens.gui.Hwnd, "Ptr", hRgn, "Int", 1)

        ZoomLens.screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
        ZoomLens.memDC := DllCall("CreateCompatibleDC", "Ptr", ZoomLens.screenDC, "Ptr")
        ZoomLens.hBmp := DllCall("CreateCompatibleBitmap", "Ptr", ZoomLens.screenDC
            , "Int", ZoomLens.LensSize, "Int", ZoomLens.LensSize, "Ptr")
        ZoomLens.oldBmp := DllCall("SelectObject", "Ptr", ZoomLens.memDC, "Ptr", ZoomLens.hBmp, "Ptr")
    }

    static Toggle() {
        ZoomLens.active := !ZoomLens.active
        if ZoomLens.active {
            ZoomLens.gui.Show("NoActivate")
            ZoomLens.timer := ObjBindMethod(ZoomLens, "_Update")
            SetTimer(ZoomLens.timer, 16)
        } else {
            if ZoomLens.timer
                SetTimer(ZoomLens.timer, 0)
            ZoomLens.gui.Hide()
        }
    }

    static _Update() {
        if !ZoomLens.active
            return

        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)

        ls := ZoomLens.LensSize
        cs := ZoomLens.CaptureSize
        half := cs // 2

        DllCall("SetStretchBltMode", "Ptr", ZoomLens.memDC, "Int", 4)
        DllCall("StretchBlt", "Ptr", ZoomLens.memDC
            , "Int", 0, "Int", 0, "Int", ls, "Int", ls
            , "Ptr", ZoomLens.screenDC
            , "Int", mx - half, "Int", my - half, "Int", cs, "Int", cs
            , "UInt", 0x00CC0020)

        ; Crosshair
        center := ls // 2
        hPen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", 0x4444FF, "Ptr")
        oldPen := DllCall("SelectObject", "Ptr", ZoomLens.memDC, "Ptr", hPen, "Ptr")
        DllCall("MoveToEx", "Ptr", ZoomLens.memDC, "Int", center - 12, "Int", center, "Ptr", 0)
        DllCall("LineTo", "Ptr", ZoomLens.memDC, "Int", center + 13, "Int", center)
        DllCall("MoveToEx", "Ptr", ZoomLens.memDC, "Int", center, "Int", center - 12, "Ptr", 0)
        DllCall("LineTo", "Ptr", ZoomLens.memDC, "Int", center, "Int", center + 13)
        DllCall("SelectObject", "Ptr", ZoomLens.memDC, "Ptr", oldPen, "Ptr")
        DllCall("DeleteObject", "Ptr", hPen)

        ; Border
        hPenB := DllCall("CreatePen", "Int", 0, "Int", 3, "UInt", 0xF7C34F, "Ptr")
        oldPenB := DllCall("SelectObject", "Ptr", ZoomLens.memDC, "Ptr", hPenB, "Ptr")
        hNull := DllCall("GetStockObject", "Int", 5, "Ptr")
        oldBr := DllCall("SelectObject", "Ptr", ZoomLens.memDC, "Ptr", hNull, "Ptr")
        DllCall("Ellipse", "Ptr", ZoomLens.memDC, "Int", 1, "Int", 1, "Int", ls - 1, "Int", ls - 1)
        DllCall("SelectObject", "Ptr", ZoomLens.memDC, "Ptr", oldBr, "Ptr")
        DllCall("SelectObject", "Ptr", ZoomLens.memDC, "Ptr", oldPenB, "Ptr")
        DllCall("DeleteObject", "Ptr", hPenB)

        ; Blit to window
        winDC := DllCall("GetDC", "Ptr", ZoomLens.gui.Hwnd, "Ptr")
        DllCall("BitBlt", "Ptr", winDC
            , "Int", 0, "Int", 0, "Int", ls, "Int", ls
            , "Ptr", ZoomLens.memDC
            , "Int", 0, "Int", 0, "UInt", 0x00CC0020)
        DllCall("ReleaseDC", "Ptr", ZoomLens.gui.Hwnd, "Ptr", winDC)

        ; Position offset from cursor
        winX := mx + 30
        winY := my + 30
        MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
        if (winX + ls > mR)
            winX := mx - ls - 30
        if (winY + ls > mB)
            winY := my - ls - 30

        DllCall("SetWindowPos", "Ptr", ZoomLens.gui.Hwnd, "Ptr", -1
            , "Int", winX, "Int", winY, "Int", 0, "Int", 0
            , "UInt", 0x0010 | 0x0001)
    }
}

; ============================================================
;  Radial Menu — GDI+ rendered pie menu on R2 hold
; ============================================================
class RadialMenu {
    static Size := 700          ; Diameter in pixels (same as ZoomLens)
    static DeadzoneSq := 64000000  ; ~8000² — stick magnitude for center/cancel
    static NumSegments := 8
    static hwnd := 0
    static gdipToken := 0
    static screenDC := 0
    static memDC := 0
    static hBmp := 0
    static oldBmp := 0
    static pGraphics := 0
    static ptSrc := 0
    static ptDst := 0
    static szBuf := 0
    static bfBuf := 0
    ; Brushes
    static bgBrush := 0
    static segBrush := 0
    static hoverBrush := 0
    static centerBrush := 0
    static linePen := 0
    static textBrush := 0
    static dimIconBrush := 0
    static textFont := 0
    static iconFont := 0
    static iconFontFamily := 0
    static centerFont := 0
    static textFormat := 0
    static fontFamily := 0
    static labelBrush := 0
    static ringPen := 0
    static innerPen := 0
    ; Menu items: [label, action_type, action_data]
    static Items := []

    static Init() {
        S := RadialMenu.Size

        ; Items: [label, type, data]
        ; type: "send" = Send keys, "run" = Run command
        ; Icons from Segoe MDL2 Assets font
        RadialMenu.Items := [
            {label: "Screenshot", icon: Chr(0xE714), type: "send", data: "#+s"},
            {label: "Discord",    icon: Chr(0xE8BD), type: "run",  data: A_AppData "\..\Local\Discord\Update.exe --processStart Discord.exe"},
            {label: "Spotify",    icon: Chr(0xE8D6), type: "run",  data: "spotify:"},
            {label: "Settings",   icon: Chr(0xE713), type: "send", data: "ms-settings:"},
            {label: "Desktop",    icon: Chr(0xE737), type: "send", data: "#d"},
            {label: "Notify",     icon: Chr(0xE7E7), type: "send", data: "#n"},
            {label: "Browser",    icon: Chr(0xE774), type: "run",  data: "brave.exe"},
            {label: "Lock",       icon: Chr(0xE72E), type: "send", data: "#l"}
        ]

        ; Ensure gdiplus.dll is loaded and reuse token
        DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        RadialMenu.gdipToken := RecordingOverlay.gdipToken

        ; Create layered window
        exStyle := 0x80000 | 0x8 | 0x80 | 0x20 | 0x08000000
        RadialMenu.hwnd := DllCall("CreateWindowEx"
            , "UInt", exStyle
            , "Str", "Static"
            , "Str", ""
            , "UInt", 0x80000000
            , "Int", 0, "Int", 0
            , "Int", S, "Int", S
            , "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")

        ; Make it circular
        hRgn := DllCall("CreateEllipticRgn", "Int", 0, "Int", 0, "Int", S, "Int", S, "Ptr")
        DllCall("SetWindowRgn", "Ptr", RadialMenu.hwnd, "Ptr", hRgn, "Int", 1)

        ; Create DC and bitmap
        RadialMenu.screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
        RadialMenu.memDC := DllCall("CreateCompatibleDC", "Ptr", RadialMenu.screenDC, "Ptr")
        RadialMenu.hBmp := DllCall("CreateCompatibleBitmap", "Ptr", RadialMenu.screenDC, "Int", S, "Int", S, "Ptr")
        RadialMenu.oldBmp := DllCall("SelectObject", "Ptr", RadialMenu.memDC, "Ptr", RadialMenu.hBmp, "Ptr")

        ; GDI+ Graphics
        pg := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", RadialMenu.memDC, "Ptr*", &pg)
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pg, "Int", 4)  ; AntiAlias
        DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", pg, "Int", 5)  ; AntiAlias
        RadialMenu.pGraphics := pg

        ; Create brushes — GTA 5 style (glass-like, semi-transparent)
        br := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xC0101018, "Ptr*", &br)
        RadialMenu.bgBrush := br

        br := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0x90282838, "Ptr*", &br)
        RadialMenu.segBrush := br

        br := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xB0505878, "Ptr*", &br)
        RadialMenu.hoverBrush := br

        br := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xC0181820, "Ptr*", &br)
        RadialMenu.centerBrush := br

        br := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFFFFFFF, "Ptr*", &br)
        RadialMenu.textBrush := br

        ; Dim icon brush (non-selected segments)
        br := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0x90CCCCCC, "Ptr*", &br)
        RadialMenu.dimIconBrush := br

        ; Thin line pen for segment dividers
        pen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0x30FFFFFF, "Float", 1.0, "Int", 2, "Ptr*", &pen)
        RadialMenu.linePen := pen

        ; Outer ring pen
        ringPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0x50FFFFFF, "Float", 2.0, "Int", 2, "Ptr*", &ringPen)
        RadialMenu.ringPen := ringPen

        ; Inner ring pen
        innerPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0x40FFFFFF, "Float", 1.5, "Int", 2, "Ptr*", &innerPen)
        RadialMenu.innerPen := innerPen

        ; Fonts via GDI+
        ff := 0
        DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &ff)
        RadialMenu.fontFamily := ff

        ; Label font (small)
        fnt := 0
        DllCall("gdiplus\GdipCreateFont", "Ptr", ff, "Float", 13.0, "Int", 0, "Int", 2, "Ptr*", &fnt)
        RadialMenu.textFont := fnt

        ; Center label font (shows selected item name)
        centerFnt := 0
        DllCall("gdiplus\GdipCreateFont", "Ptr", ff, "Float", 16.0, "Int", 1, "Int", 2, "Ptr*", &centerFnt)
        RadialMenu.centerFont := centerFnt

        ; Icon font (large Segoe UI Symbol / Segoe MDL2 Assets for icons)
        ffIcon := 0
        DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe MDL2 Assets", "Ptr", 0, "Ptr*", &ffIcon)
        if !ffIcon
            ffIcon := ff  ; Fallback to Segoe UI
        RadialMenu.iconFontFamily := ffIcon

        fntIcon := 0
        DllCall("gdiplus\GdipCreateFont", "Ptr", ffIcon, "Float", 60.0, "Int", 0, "Int", 2, "Ptr*", &fntIcon)
        RadialMenu.iconFont := fntIcon

        sf := 0
        DllCall("gdiplus\GdipCreateStringFormat", "Int", 0, "Int", 0, "Ptr*", &sf)
        DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", sf, "Int", 1)       ; Center
        DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", sf, "Int", 1)   ; Center
        RadialMenu.textFormat := sf

        ; Dim text brush for labels
        dimBr := 0
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xBBCCCCCC, "Ptr*", &dimBr)
        RadialMenu.labelBrush := dimBr

        ; UpdateLayeredWindow buffers
        RadialMenu.ptSrc := Buffer(8, 0)
        RadialMenu.ptDst := Buffer(8, 0)
        RadialMenu.szBuf := Buffer(8, 0)
        NumPut("Int", S, RadialMenu.szBuf, 0)
        NumPut("Int", S, RadialMenu.szBuf, 4)
        RadialMenu.bfBuf := Buffer(4, 0)
        NumPut("UChar", 0, RadialMenu.bfBuf, 0)
        NumPut("UChar", 0, RadialMenu.bfBuf, 1)
        NumPut("UChar", 255, RadialMenu.bfBuf, 2)
        NumPut("UChar", 1, RadialMenu.bfBuf, 3)   ; AC_SRC_ALPHA
    }

    static Show(mx, my) {
        if State.RadialVisible
            return
        State.RadialVisible := true
        State.RadialSelected := -1
        State.RadialOriginX := mx
        State.RadialOriginY := my

        S := RadialMenu.Size
        winX := mx - S // 2
        winY := my - S // 2

        ; Clamp to screen
        MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
        if (winX < mL)
            winX := mL
        if (winY < mT)
            winY := mT
        if (winX + S > mR)
            winX := mR - S
        if (winY + S > mB)
            winY := mB - S

        NumPut("Int", winX, RadialMenu.ptDst, 0)
        NumPut("Int", winY, RadialMenu.ptDst, 4)

        RadialMenu._Draw(-1)

        DllCall("ShowWindow", "Ptr", RadialMenu.hwnd, "Int", 8)  ; SW_SHOWNA
        DllCall("SetWindowPos", "Ptr", RadialMenu.hwnd, "Ptr", -1
            , "Int", winX, "Int", winY, "Int", S, "Int", S
            , "UInt", 0x0040 | 0x0010)  ; SWP_SHOWWINDOW | SWP_NOACTIVATE
    }

    static Hide() {
        if !State.RadialVisible
            return
        State.RadialVisible := false
        DllCall("ShowWindow", "Ptr", RadialMenu.hwnd, "Int", 0)  ; SW_HIDE
    }

    static Update(rx, ry) {
        if !State.RadialVisible
            return

        magSq := rx * rx + ry * ry
        if (magSq < RadialMenu.DeadzoneSq) {
            ; Center = cancel
            if (State.RadialSelected != -1) {
                State.RadialSelected := -1
                RadialMenu._Draw(-1)
            }
            return
        }

        ; Calculate angle: atan2(-ry, rx) because Y is inverted on stick
        ; Map to 0..2π, then to segment index
        angle := ATan2(-ry, rx)
        if (angle < 0)
            angle += 2 * 3.14159265

        ; Offset so segment 0 (top) is centered at 12 o'clock
        ; Segment 0 = top = angle π/2, going clockwise
        ; Remap: rotate by +π/2 so 0 = top, then clockwise
        segAngle := 2 * 3.14159265 / RadialMenu.NumSegments
        remapped := Mod(angle + 3.14159265 / 2 + segAngle / 2, 2 * 3.14159265)
        idx := Integer(remapped / segAngle)
        if (idx >= RadialMenu.NumSegments)
            idx := RadialMenu.NumSegments - 1

        if (idx != State.RadialSelected) {
            State.RadialSelected := idx
            RadialMenu._Draw(idx)
        }
    }

    static Execute(idx) {
        if (idx < 0 || idx >= RadialMenu.Items.Length)
            return  ; Cancel

        item := RadialMenu.Items[idx + 1]  ; AHK is 1-indexed
        ; Small delay to let menu fully close before sending keys
        SetTimer(() => RadialMenu._RunAction(item), -50)
    }

    static _RunAction(item) {
        if (item.type = "send")
            Send(item.data)
        else if (item.type = "run") {
            try Run(item.data)
        }
    }

    static _Draw(hovered) {
        pg := RadialMenu.pGraphics
        S := RadialMenu.Size
        half := S / 2.0
        numSeg := RadialMenu.NumSegments
        segAngle := 360.0 / numSeg
        pi := 3.14159265
        innerR := 100.0
        outerR := half - 4.0

        ; Clear
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", pg, "UInt", 0x00000000)

        ; Background disc
        DllCall("gdiplus\GdipFillEllipse", "Ptr", pg, "Ptr", RadialMenu.bgBrush
            , "Float", 2.0, "Float", 2.0, "Float", Float(S - 4), "Float", Float(S - 4))

        ; Draw segments
        loop numSeg {
            i := A_Index - 1
            startDeg := -90 + (i * segAngle) - (segAngle / 2)
            brush := (i = hovered) ? RadialMenu.hoverBrush : RadialMenu.segBrush

            ; Pie slice (outer ring)
            DllCall("gdiplus\GdipFillPie", "Ptr", pg, "Ptr", brush
                , "Float", half - outerR, "Float", half - outerR
                , "Float", outerR * 2, "Float", outerR * 2
                , "Float", Float(startDeg), "Float", Float(segAngle - 1.0))
        }

        ; Cut out inner circle (re-fill with center color to create donut)
        DllCall("gdiplus\GdipFillEllipse", "Ptr", pg, "Ptr", RadialMenu.centerBrush
            , "Float", half - innerR, "Float", half - innerR
            , "Float", innerR * 2, "Float", innerR * 2)

        ; Divider lines
        loop numSeg {
            i := A_Index - 1
            lineRad := (-90 + (i * segAngle) - (segAngle / 2)) * pi / 180
            x1 := half + innerR * Cos(lineRad)
            y1 := half + innerR * Sin(lineRad)
            x2 := half + outerR * Cos(lineRad)
            y2 := half + outerR * Sin(lineRad)
            DllCall("gdiplus\GdipDrawLine", "Ptr", pg, "Ptr", RadialMenu.linePen
                , "Float", Float(x1), "Float", Float(y1)
                , "Float", Float(x2), "Float", Float(y2))
        }

        ; Outer ring border
        DllCall("gdiplus\GdipDrawEllipse", "Ptr", pg, "Ptr", RadialMenu.ringPen
            , "Float", half - outerR, "Float", half - outerR
            , "Float", outerR * 2, "Float", outerR * 2)

        ; Inner ring border
        DllCall("gdiplus\GdipDrawEllipse", "Ptr", pg, "Ptr", RadialMenu.innerPen
            , "Float", half - innerR, "Float", half - innerR
            , "Float", innerR * 2, "Float", innerR * 2)

        ; Draw icons in segments
        loop numSeg {
            i := A_Index - 1
            midDeg := -90 + (i * segAngle)
            midRad := midDeg * pi / 180
            iconR := (innerR + outerR) / 2
            ix := half + iconR * Cos(midRad)
            iy := half + iconR * Sin(midRad)
            item := RadialMenu.Items[i + 1]
            iconBrush := (i = hovered) ? RadialMenu.textBrush : RadialMenu.dimIconBrush

            DllCall("gdiplus\GdipDrawString", "Ptr", pg
                , "WStr", item.icon, "Int", -1
                , "Ptr", RadialMenu.iconFont
                , "Ptr", RadialMenu._MakeRectF(ix - 50, iy - 40, 100, 80)
                , "Ptr", RadialMenu.textFormat
                , "Ptr", iconBrush)
        }

        ; Center text — show selected item name or "Cancel"
        centerLabel := (hovered >= 0 && hovered < RadialMenu.Items.Length)
            ? RadialMenu.Items[hovered + 1].label
            : "Cancel"
        DllCall("gdiplus\GdipDrawString", "Ptr", pg
            , "WStr", centerLabel, "Int", -1
            , "Ptr", RadialMenu.centerFont
            , "Ptr", RadialMenu._MakeRectF(half - 80, half - 14, 160, 28)
            , "Ptr", RadialMenu.textFormat
            , "Ptr", RadialMenu.textBrush)

        ; Update layered window
        DllCall("UpdateLayeredWindow", "Ptr", RadialMenu.hwnd
            , "Ptr", RadialMenu.screenDC
            , "Ptr", RadialMenu.ptDst
            , "Ptr", RadialMenu.szBuf
            , "Ptr", RadialMenu.memDC
            , "Ptr", RadialMenu.ptSrc
            , "UInt", 0
            , "Ptr", RadialMenu.bfBuf
            , "UInt", 2)
    }

    static _rectBuf := Buffer(16, 0)
    static _MakeRectF(x, y, w, h) {
        NumPut("Float", Float(x), RadialMenu._rectBuf, 0)
        NumPut("Float", Float(y), RadialMenu._rectBuf, 4)
        NumPut("Float", Float(w), RadialMenu._rectBuf, 8)
        NumPut("Float", Float(h), RadialMenu._rectBuf, 12)
        return RadialMenu._rectBuf.Ptr
    }
}

; Helper: atan2 (AHK v2 doesn't have built-in atan2)
ATan2(y, x) {
    if (x > 0)
        return ATan(y / x)
    if (x < 0 && y >= 0)
        return ATan(y / x) + 3.14159265
    if (x < 0 && y < 0)
        return ATan(y / x) - 3.14159265
    if (x = 0 && y > 0)
        return 3.14159265 / 2
    if (x = 0 && y < 0)
        return -3.14159265 / 2
    return 0
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

; NOTE: Run block_controller_keys.py separately to block DsHidMini
; phantom keyboard events (VK codes 0xC8, 0xCB-0xCE etc.)

HUD.Init()
ClipboardToast.Init()
RecordingOverlay.Init()
ZoomLens.Init()
RadialMenu.Init()

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

; Launch ZoomLens as separate process
zoomScript := A_ScriptDir "\ZoomLens.ahk"
if FileExist(zoomScript)
    Run('"' A_AhkPath '" "' zoomScript '"',, "Hide")

; Launch Whisper server
Whisper.LaunchServer()

; Clean up on exit
OnExit(ShutdownAll)
ShutdownAll(*) {
    Whisper.Shutdown()
    ; Close ZoomLens
    DetectHiddenWindows(true)
    try WinClose(A_ScriptDir "\ZoomLens.ahk ahk_class AutoHotkey")
}

SetTimer(MainLoop, Config.PollRate)
SetTimer(GameDetection, 2000)  ; Check every 2 seconds

; ============================================================
;  Game detection — auto-pause when a game is in foreground
; ============================================================
IsGameRunning() {
    try {
        hwnd := WinGetID("A")
        if !hwnd
            return false

        ; Check if foreground window is fullscreen exclusive
        ; (covers entire screen, not a desktop/taskbar/browser)
        WinGetPos(&x, &y, &w, &h, hwnd)
        MonitorGetWorkArea(, &mL, &mT, &mR, &mB)
        screenW := SysGet(0)   ; SM_CXSCREEN
        screenH := SysGet(1)   ; SM_CYSCREEN

        ; Must cover entire screen (not just work area)
        isFullscreen := (x <= 0 && y <= 0 && w >= screenW && h >= screenH)

        if !isFullscreen
            return false

        ; Get process name
        procName := StrLower(WinGetProcessName(hwnd))
        winClass := WinGetClass(hwnd)

        ; Whitelist — known non-game fullscreen apps (DON'T pause for these)
        whitelist := ["explorer.exe", "brave.exe", "chrome.exe", "firefox.exe", "msedge.exe"
            , "vlc.exe", "spotify.exe", "discord.exe", "code.exe"
            , "windowsterminal.exe", "wt.exe", "notepad.exe"
            , "powerpnt.exe", "winword.exe", "excel.exe"
            , "mpc-hc64.exe", "mpc-hc.exe", "mpv.exe"
            , "snippingtool.exe", "screenclippinghost.exe"
            , "taskmgr.exe", "powershell.exe", "pwsh.exe"]

        for _, name in whitelist {
            if (procName = name)
                return false
        }

        ; If fullscreen and NOT whitelisted → probably a game
        return true
    }
    return false
}

GameDetection() {
    gameRunning := IsGameRunning()

    if (gameRunning && !State.GamePaused) {
        ; Game detected — auto-pause
        State.GamePaused := true
        State.Active := false
        ToolTip("DS3Mouse AUTO-PAUSED (game detected)")
        SetTimer(() => ToolTip(), -3000)
        ; Release any held buttons
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
        HUD.Hide()
    } else if (!gameRunning && State.GamePaused) {
        ; Game exited — auto-resume
        State.GamePaused := false
        State.Active := true
        ToolTip("DS3Mouse RESUMED")
        SetTimer(() => ToolTip(), -3000)
    }
}

; ============================================================
;  Main loop
; ============================================================
MainLoop() {
    gp := XI.GetState(Config.UserIndex)
    if !gp.connected
        return

    buttons := gp.buttons

    ; ── Guide/PS button toggle (works even when paused) ──
    guideNow := (buttons & 0x0400) != 0  ; XINPUT.GUIDE
    if (guideNow && !State.PrevGuide) {
        State.Active := !State.Active
        State.GamePaused := false  ; Manual override clears auto-pause
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

    ; ── Cache frequently used values ──
    lx := gp.lx, ly := gp.ly, rx := gp.rx, ry := gp.ry
    lt := gp.lt, rt := gp.rt

    ; ── L1 held? Show/hide HUD ──
    l1Held := (buttons & 0x0100) != 0  ; XINPUT.LEFT_SHOULDER
    if (l1Held && !State.PrevL1)
        HUD.Show()
    else if (!l1Held && State.PrevL1)
        HUD.Hide()
    State.PrevL1 := l1Held

    ; ── LEFT STICK → Radial menu or Cursor ──
    if State.RadialVisible {
        RadialMenu.Update(lx, ly)
    } else if (lx * lx + ly * ly > 9000000) {  ; CursorDeadzone² = 3000² = 9M
        MoveCursor(lx, ly)
    } else if (State.MoveAccumX != 0.0 || State.MoveAccumY != 0.0) {
        State.MoveAccumX := 0.0
        State.MoveAccumY := 0.0
    }

    ; ── RIGHT STICK → Scroll (skip if in deadzone) ──
    if (rx * rx + ry * ry > 25000000) {  ; ScrollDeadzone² = 5000² = 25M
        HandleStickScroll(rx, ry)
    } else {
        State.ScrollAccumV := 0.0
        State.ScrollAccumH := 0.0
    }

    ; ── TRIGGERS → Click ──
    HandleTriggers(lt, rt)

    ; ── D-PAD (only real d-pad presses, ignore if left stick is active) ──
    ; XInput leaks stick input into d-pad bits — suppress d-pad when stick moves
    ; BUT: always allow d-pad when L1 is held (modifier commands need d-pad)
    if (l1Held || lx * lx + ly * ly < 9000000)  ; ~3000 mag — d-pad physically bleeds ~2000 into stick
        HandleDPad(buttons, l1Held)
    else {
        State.DpadActive := false
        State.DpadRepeating := false
    }

    ; ── Face buttons + shoulders ──
    HandleButtons(buttons, l1Held)

    State.PrevButtons := buttons
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

; Send a key while releasing ALL phantom modifiers from DsHidMini XInput.
; DsHidMini sends vkC8 (LCtrl) and possibly other virtual keys when
; controller buttons are held, corrupting Send(). This releases everything first.
CleanSend(keys) {
    SendInput("{LCtrl Up}{RCtrl Up}{LShift Up}{RShift Up}{LAlt Up}{RAlt Up}{LWin Up}{RWin Up}")
    Sleep(10)
    SendInput(keys)
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
        ; Open radial menu instead of click
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        RadialMenu.Show(mx, my)
        State.R2Down := true
    } else if (!r2Now && State.R2Down) {
        ; Release → execute selected action or cancel
        RadialMenu.Execute(State.RadialSelected)
        RadialMenu.Hide()
        State.R2Down := false
    }
}

; ============================================================
;  D-Pad — tick-based with cooldown to prevent double-triggers
; ============================================================
HandleDPad(buttons, l1Held) {
    dpad := buttons & 0x000F
    now := A_TickCount

    ; --- Released ---
    if (dpad = 0) {
        if (State.DpadActive) {
            ; Mark release time for cooldown
            State.DpadReleaseTime := now
            State.DpadActive := false
            State.DpadHeldMs := 0
        }
        return
    }

    ; --- Pressed ---
    ; Determine the primary direction (pick one bit only — prevents diagonal noise)
    primary := 0
    if (dpad & XINPUT.DPAD_UP)
        primary := XINPUT.DPAD_UP
    else if (dpad & XINPUT.DPAD_DOWN)
        primary := XINPUT.DPAD_DOWN
    else if (dpad & XINPUT.DPAD_LEFT)
        primary := XINPUT.DPAD_LEFT
    else if (dpad & XINPUT.DPAD_RIGHT)
        primary := XINPUT.DPAD_RIGHT

    if (primary = 0)
        return

    if (!State.DpadActive) {
        ; New press — enforce cooldown from last release (prevents double-triggers)
        if (now - State.DpadReleaseTime < 80)
            return  ; Too soon after release, ignore

        State.DpadActive := true
        State.DpadDirection := primary
        State.DpadHeldMs := 0
        State.DpadFired := false

        ; Fire immediately on press
        DPadAction(primary, l1Held)
        State.DpadFired := true
        return
    }

    ; Held — same direction only (ignore direction changes while held)
    if (primary != State.DpadDirection)
        return

    ; Accumulate hold time for repeat
    State.DpadHeldMs += Config.PollRate
    threshold := State.DpadFired ? Config.DpadRepeatInterval : Config.DpadRepeatDelay
    ; First repeat uses delay, subsequent repeats use interval
    if (!State.DpadRepeating && State.DpadHeldMs >= Config.DpadRepeatDelay) {
        State.DpadRepeating := true
        State.DpadHeldMs := 0
        DPadAction(primary, l1Held)
    } else if (State.DpadRepeating && State.DpadHeldMs >= Config.DpadRepeatInterval) {
        State.DpadHeldMs := 0
        DPadAction(primary, l1Held)
    }
}

DPadAction(dpad, l1Held) {
    ; If Alt+Tab is active, navigate the switcher and reset the confirm timer
    ; Must keep Alt held — use {Blind} to avoid Send releasing modifiers
    if State.AltTabActive {
        if (dpad & XINPUT.DPAD_LEFT) || (dpad & XINPUT.DPAD_UP)
            Send("{Blind}+{Tab}")  ; Shift+Tab = previous window (Alt stays held)
        else if (dpad & XINPUT.DPAD_RIGHT) || (dpad & XINPUT.DPAD_DOWN)
            Send("{Blind}{Tab}")   ; Tab = next window (Alt stays held)
        ; Reset auto-confirm timer on each navigation
        SetTimer(AltTabConfirm, -5000)
        return
    }

    if l1Held {
        mediaScript := A_ScriptDir "\media_control.py"
        if (dpad & XINPUT.DPAD_UP) {
            ToolTip("L1+UP: Volume Up")
            SetTimer(() => ToolTip(), -1000)
            Run('pythonw -c "import ctypes; ctypes.windll.user32.keybd_event(0xAF,0,0,0); ctypes.windll.user32.keybd_event(0xAF,0,2,0)"',, "Hide")
        }
        if (dpad & XINPUT.DPAD_DOWN) {
            ToolTip("L1+DOWN: Volume Down")
            SetTimer(() => ToolTip(), -1000)
            Run('pythonw -c "import ctypes; ctypes.windll.user32.keybd_event(0xAE,0,0,0); ctypes.windll.user32.keybd_event(0xAE,0,2,0)"',, "Hide")
        }
        if (dpad & XINPUT.DPAD_LEFT) {
            ToolTip("L1+LEFT: Prev Track")
            SetTimer(() => ToolTip(), -1000)
            Run('pythonw "' mediaScript '" prev',, "Hide")
        }
        if (dpad & XINPUT.DPAD_RIGHT) {
            ToolTip("L1+RIGHT: Next Track")
            SetTimer(() => ToolTip(), -1000)
            Run('pythonw "' mediaScript '" next',, "Hide")
        }
        return
    } else {
        {
            if (dpad & XINPUT.DPAD_UP)
                CleanSend("{Up}")
            if (dpad & XINPUT.DPAD_DOWN)
                CleanSend("{Down}")
            if (dpad & XINPUT.DPAD_LEFT)
                CleanSend("{Left}")
            if (dpad & XINPUT.DPAD_RIGHT)
                CleanSend("{Right}")
        }
    }
}

; ============================================================
;  Face buttons + shoulders
; ============================================================
HandleButtons(buttons, l1Held) {
    ; If Alt+Tab is active, Cross confirms and Circle cancels
    if State.AltTabActive {
        if BtnPressed(buttons, XINPUT.A) {
            ; Confirm — release Alt to select the focused window
            SetTimer(AltTabConfirm, 0)  ; Cancel auto-timer
            Send("{Alt Up}")
            State.AltTabActive := false
            State.AltTabJustClosed := true  ; Block Cross click until released
            return
        }
        if BtnPressed(buttons, XINPUT.B) {
            ; Cancel — press Escape then release Alt
            SetTimer(AltTabConfirm, 0)
            Send("{Escape}{Alt Up}")
            State.AltTabActive := false
            return
        }
        return  ; Block other buttons while Alt+Tab is open
    }

    ; A / Cross — hold for drag, or Enter with L1
    crossNow := BtnHeld(buttons, XINPUT.A)
    ; Block Cross until released after Alt+Tab confirm
    if (State.AltTabJustClosed) {
        if !crossNow
            State.AltTabJustClosed := false
        ; Skip all Cross logic while button still held
    } else if l1Held {
        if BtnPressed(buttons, XINPUT.A)
            CleanSend("{Enter}")
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
            CleanSend("{Escape}")
        else
            Click("Right")
    }

    ; X / Square — hold to repeat Backspace, or Clear All with L1
    sqNow := BtnHeld(buttons, XINPUT.X)
    if l1Held {
        if BtnPressed(buttons, XINPUT.X)
            CleanSend("^a{Delete}")
    } else {
        if (sqNow && !State.SquareHeld) {
            CleanSend("{Backspace}")
            State.SquareHeld := true
            State.SquareRepeatTick := 0
        } else if (sqNow && State.SquareHeld) {
            State.SquareRepeatTick += Config.PollRate
            if (State.SquareRepeatTick >= 30) {
                State.SquareRepeatTick := 0
                CleanSend("{Backspace}")
            }
        } else if !sqNow {
            State.SquareHeld := false
            State.SquareRepeatTick := 0
        }
    }

    ; Y / Triangle — toggles between Copy and Paste (Tab with L1)
    if BtnPressed(buttons, XINPUT.Y) {
        if l1Held {
            CleanSend("{Tab}")
        } else {
            if State.TriangleNextPaste {
                CleanSend("^v")
                State.TriangleNextPaste := false
                ToolTip("Pasted")
                SetTimer(() => ToolTip(), -1500)
            } else {
                CleanSend("^c")
                Sleep(50)
                State.TriangleNextPaste := true
                ToolTip("Copied")
                SetTimer(() => ToolTip(), -1500)
            }
        }
    }

    ; R1 — hold to dictate (local Whisper)
    ; Normal R1 = dictation (types text + Enter)
    ; L1 + R1 = voice command (executes keyboard shortcut)
    r1Now := BtnHeld(buttons, XINPUT.RIGHT_SHOULDER)
    if (r1Now && !State.R1Dictating && !State.WaitingForTranscription) {
        ; Delete old result file
        resultFile := A_ScriptDir "\whisper_result.txt"
        if FileExist(resultFile)
            FileDelete(resultFile)
        Whisper.StartRecording()
        State.R1Dictating := true
        State.R1IsVoiceCommand := l1Held  ; Remember if L1 was held at start
        RecordingOverlay.Show()
        if l1Held
            HUD.SetMode("voice")
    } else if (!r1Now && State.R1Dictating) {
        State.R1Dictating := false
        HUD.SetMode("normal")
        RecordingOverlay.ShowTranscribing()
        ; Voice command mode forces English transcription
        Whisper._Send(State.R1IsVoiceCommand ? "STOP_EN`n" : "STOP`n")
        State.WaitingForTranscription := true
        State.TranscriptionStartTime := A_TickCount
        SetTimer(PollTranscriptionResult, 100)
    }

    ; Start → Windows Start menu
    if BtnPressed(buttons, XINPUT.START)
        CleanSend("{LWin}")

    ; Back/Select → Alt+Tab window switcher
    if BtnPressed(buttons, XINPUT.BACK) {
        if State.AltTabActive {
            ; Already open — tab to next window and reset timer
            SendInput("{Blind}{Tab}")
            SetTimer(AltTabConfirm, -5000)
        } else {
            ; Open Alt+Tab switcher — release phantom modifiers first
            SendInput("{LCtrl Up}{RCtrl Up}{LShift Up}{RShift Up}")
            Sleep(10)
            SendInput("{Alt Down}{Tab}")
            State.AltTabActive := true
            SetTimer(AltTabConfirm, -5000)
        }
    }

    ; L3 → toggle sniper + zoom
    l3Now := BtnHeld(buttons, XINPUT.LEFT_THUMB)
    if (l3Now && !State.PrevL3) {
        ; Block d-pad briefly so stick wiggle during click doesn't send arrows
        State.DpadActive := false
        State.DpadReleaseTime := A_TickCount + 400
        State.Sniper := !State.Sniper
        ZoomLens.Toggle()
        ToolTip(State.Sniper ? "Sniper + Zoom ON" : "Sniper + Zoom OFF")
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
;  Alt+Tab confirm — releases Alt to select the focused window
; ============================================================
AltTabConfirm() {
    if !State.AltTabActive
        return
    Send("{Alt Up}")
    State.AltTabActive := false
}

; ============================================================
;  Poll for transcription result file (non-blocking)
; ============================================================
PollTranscriptionResult() {
    resultFile := A_ScriptDir "\whisper_result.txt"

    if !FileExist(resultFile) {
        ; Timeout after 35 seconds — give up
        if (A_TickCount - State.TranscriptionStartTime > 35000) {
            SetTimer(PollTranscriptionResult, 0)
            State.WaitingForTranscription := false
            RecordingOverlay.Hide()
            ToolTip("Transcription timed out")
            SetTimer(() => ToolTip(), -2000)
        }
        return
    }

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

    ; Voice command mode — match text to keyboard commands
    if State.R1IsVoiceCommand {
        ExecuteVoiceCommand(text)
        return
    }

    ; Normal dictation — type the text and send Enter
    SendText(text)
    SetTimer(() => Send("{Enter}"), -Config.DictateEnterDelay)
}

; ============================================================
;  Voice Commands (L1 + R1) — keyboard shortcuts by voice
; ============================================================
ExecuteVoiceCommand(text) {
    ; Normalize: lowercase, trim, remove punctuation
    cmd := Trim(StrLower(text))
    cmd := RegExReplace(cmd, "[,!?;:\x27\x22\-\*\#\(\)\[\]]", "")  ; Keep dots for URLs
    cmd := RegExReplace(cmd, "\s+", " ")

    ; Match against known commands
    matched := true
    if RegExMatch(cmd, "^(enter|confirm|send|submit)$")
        CleanSend("{Enter}")
    else if RegExMatch(cmd, "^(escape|cancel|close|exit|esc)$")
        CleanSend("{Escape}")
    else if RegExMatch(cmd, "^(copy)$")
        CleanSend("^c")
    else if RegExMatch(cmd, "^(paste)$")
        CleanSend("^v")
    else if RegExMatch(cmd, "^(cut)$")
        CleanSend("^x")
    else if RegExMatch(cmd, "^(undo)$")
        CleanSend("^z")
    else if RegExMatch(cmd, "^(redo)$")
        CleanSend("^y")
    else if RegExMatch(cmd, "^(select all|select everything)$")
        CleanSend("^a")
    else if RegExMatch(cmd, "^(backspace|delete that|erase)$")
        CleanSend("{Backspace}")
    else if RegExMatch(cmd, "^(delete)$")
        CleanSend("{Delete}")
    else if RegExMatch(cmd, "^(space|spacebar)$")
        CleanSend("{Space}")
    else if RegExMatch(cmd, "^(tab|next field)$")
        CleanSend("{Tab}")
    else if RegExMatch(cmd, "^(shift tab|previous field)$")
        CleanSend("+{Tab}")
    else if RegExMatch(cmd, "^(home)$")
        CleanSend("{Home}")
    else if RegExMatch(cmd, "^(end)$")
        CleanSend("{End}")
    else if RegExMatch(cmd, "^(page up)$")
        CleanSend("{PgUp}")
    else if RegExMatch(cmd, "^(page down)$")
        CleanSend("{PgDn}")
    else if RegExMatch(cmd, "^(up|arrow up)$")
        CleanSend("{Up}")
    else if RegExMatch(cmd, "^(down|arrow down)$")
        CleanSend("{Down}")
    else if RegExMatch(cmd, "^(left|arrow left)$")
        CleanSend("{Left}")
    else if RegExMatch(cmd, "^(right|arrow right)$")
        CleanSend("{Right}")
    else if RegExMatch(cmd, "^(save)$")
        CleanSend("^s")
    else if RegExMatch(cmd, "^(find|search)$")
        CleanSend("^f")
    else if RegExMatch(cmd, "^(new tab)$")
        CleanSend("^t")
    else if RegExMatch(cmd, "^(close tab)$")
        CleanSend("^w")
    else if RegExMatch(cmd, "^(reopen tab|restore tab)$")
        CleanSend("^+t")
    else if RegExMatch(cmd, "^(next tab)$")
        CleanSend("^{Tab}")
    else if RegExMatch(cmd, "^(previous tab)$")
        CleanSend("^+{Tab}")
    else if RegExMatch(cmd, "^(refresh|reload)$")
        CleanSend("{F5}")
    else if RegExMatch(cmd, "^(full ?screen)$")
        CleanSend("{F11}")
    else if RegExMatch(cmd, "^(minimize)$")
        WinMinimize("A")
    else if RegExMatch(cmd, "^(maximize)$")
        WinMaximize("A")
    else if RegExMatch(cmd, "^(close window|alt f4)$")
        CleanSend("!{F4}")
    else if RegExMatch(cmd, "^(screenshot|print screen)$")
        CleanSend("{PrintScreen}")
    else if RegExMatch(cmd, "^(snip|snipping)$")
        CleanSend("#+s")
    else if RegExMatch(cmd, "^(lock|lock screen)$")
        CleanSend("#l")
    else if RegExMatch(cmd, "^(desktop|show desktop)$")
        CleanSend("#d")
    else if RegExMatch(cmd, "^(task manager)$")
        CleanSend("^+{Escape}")
    ; App launchers
    else if RegExMatch(cmd, "^(open |launch |start )?(spotify)$")
        Run("spotify:")
    else if RegExMatch(cmd, "^(open |launch |start )?(chrome|brave|browser)$")
        Run("https://")
    else if RegExMatch(cmd, "^(open |launch |start )?(discord)$")
        Run("discord:")
    else if RegExMatch(cmd, "^(open |launch |start )?(explorer|file ?manager|files)$")
        Run("explorer.exe")
    ; Media controls (via Python — bypasses phantom keys entirely)
    else if RegExMatch(cmd, "^(play|pause|paus|play pause|spela|pausa)$")
        Run('pythonw "' A_ScriptDir '\media_control.py" play',, "Hide")
    else if RegExMatch(cmd, "^(next|next track|skip|nästa|nästa låt)$")
        Run('pythonw "' A_ScriptDir '\media_control.py" next',, "Hide")
    else if RegExMatch(cmd, "^(previous|previous track|go back|förra|förra låten|tillbaka)$")
        Run('pythonw "' A_ScriptDir '\media_control.py" prev',, "Hide")
    else if RegExMatch(cmd, "^(mute|unmute)$")
        CleanSend("{Volume_Mute}")
    else if RegExMatch(cmd, "^(volume up|louder)$")
        CleanSend("{Volume_Up 5}")
    else if RegExMatch(cmd, "^(volume down|quieter|softer)$")
        CleanSend("{Volume_Down 5}")
    ; Browser zoom
    else if RegExMatch(cmd, "^(zoom in)$")
        CleanSend("^{=}")
    else if RegExMatch(cmd, "^(zoom out)$")
        CleanSend("^{-}")
    else if RegExMatch(cmd, "^(zoom reset|reset zoom)$")
        CleanSend("^0")
    ; Window snapping
    else if RegExMatch(cmd, "^(snap left|left half)$")
        CleanSend("#{Left}")
    else if RegExMatch(cmd, "^(snap right|right half)$")
        CleanSend("#{Right}")
    else if RegExMatch(cmd, "^(snap up|top half)$")
        CleanSend("#{Up}")
    else if RegExMatch(cmd, "^(snap down|bottom half)$")
        CleanSend("#{Down}")
    ; More app launchers
    else if RegExMatch(cmd, "^(open |launch |start )?(settings)$")
        Run("ms-settings:")
    else if RegExMatch(cmd, "^(open |launch |start )?(notepad|text editor)$")
        Run("notepad.exe")
    else if RegExMatch(cmd, "^(open |launch |start )?(calculator|calc)$")
        Run("calc.exe")
    else if RegExMatch(cmd, "^(open |launch |start )?(terminal|command prompt|cmd)$")
        Run("wt.exe")
    else if RegExMatch(cmd, "^(open |launch |start )?(claude|cloud)$")
        Run(A_AppData "\..\Local\AnthropicClaude\claude.exe")
    ; Search — "search for X", "google X"
    else if RegExMatch(cmd, "^(search for |search |google |look up |sök på |sök )(.*)", &searchMatch) {
        query := searchMatch[2]
        Run("https://www.google.com/search?q=" query)
    }
    ; Known websites — just say the name, no need for .com/.se
    else {
        urlCmd := RegExReplace(cmd, "^(open\s*|go\s*to\s*|navigate\s*to\s*|visit\s*|öppna\s*)", "")
        urlCmd := Trim(urlCmd)
        ; Also handle Whisper merging "open" into the word
        if !RegExMatch(urlCmd, "\.(com|se|net|org|io|dev|ai|co|uk|de|no|dk|fi)")
            urlCmd := RegExReplace(urlCmd, "^(open|goto|visit|öppna)", "")
        urlCmd := Trim(urlCmd)

        ; Lookup table for common sites
        sites := Map(
            "youtube", "https://youtube.com",
            ; Search & Social
            "google", "https://google.com",
            "gmail", "https://gmail.com",
            "google maps", "https://maps.google.com",
            "maps", "https://maps.google.com",
            "google drive", "https://drive.google.com",
            "drive", "https://drive.google.com",
            "google docs", "https://docs.google.com",
            "youtube", "https://youtube.com",
            "reddit", "https://reddit.com",
            "twitter", "https://twitter.com",
            "x", "https://x.com",
            "facebook", "https://facebook.com",
            "instagram", "https://instagram.com",
            "linkedin", "https://linkedin.com",
            "tiktok", "https://tiktok.com",
            "snapchat", "https://web.snapchat.com",
            "pinterest", "https://pinterest.com",
            "threads", "https://threads.net",
            "whatsapp", "https://web.whatsapp.com",
            "telegram", "https://web.telegram.org",
            "discord", "https://discord.com/app",
            ; Video & Streaming
            "netflix", "https://netflix.com",
            "twitch", "https://twitch.tv",
            "hbo", "https://play.hbomax.com",
            "hbo max", "https://play.hbomax.com",
            "disney", "https://disneyplus.com",
            "disney plus", "https://disneyplus.com",
            "prime video", "https://primevideo.com",
            "viaplay", "https://viaplay.se",
            "crunchyroll", "https://crunchyroll.com",
            "svt play", "https://svtplay.se",
            "svt", "https://svtplay.se",
            "tv4 play", "https://tv4play.se",
            ; Music
            "spotify", "https://open.spotify.com",
            "soundcloud", "https://soundcloud.com",
            "apple music", "https://music.apple.com",
            ; Shopping (Swedish + Global)
            "amazon", "https://amazon.se",
            "ikea", "https://ikea.se",
            "blocket", "https://blocket.se",
            "tradera", "https://tradera.com",
            "prisjakt", "https://prisjakt.nu",
            "klarna", "https://klarna.com",
            "cdon", "https://cdon.se",
            "zalando", "https://zalando.se",
            "hm", "https://hm.com",
            "h&m", "https://hm.com",
            "elgiganten", "https://elgiganten.se",
            "inet", "https://inet.se",
            "komplett", "https://komplett.se",
            "webhallen", "https://webhallen.com",
            "mediamarkt", "https://mediamarkt.se",
            "ebay", "https://ebay.com",
            "aliexpress", "https://aliexpress.com",
            "wish", "https://wish.com",
            ; Dev & Tech
            "github", "https://github.com",
            "gitlab", "https://gitlab.com",
            "stackoverflow", "https://stackoverflow.com",
            "stack overflow", "https://stackoverflow.com",
            "npm", "https://npmjs.com",
            "codepen", "https://codepen.io",
            "vercel", "https://vercel.com",
            "netlify", "https://netlify.com",
            "figma", "https://figma.com",
            "notion", "https://notion.so",
            "trello", "https://trello.com",
            ; AI
            "chatgpt", "https://chat.openai.com",
            "claude", "https://claude.ai",
            "perplexity", "https://perplexity.ai",
            "midjourney", "https://midjourney.com",
            "hugging face", "https://huggingface.co",
            ; News & Info
            "wikipedia", "https://wikipedia.org",
            "aftonbladet", "https://aftonbladet.se",
            "expressen", "https://expressen.se",
            "dn", "https://dn.se",
            "svd", "https://svd.se",
            "bbc", "https://bbc.com",
            "cnn", "https://cnn.com",
            "hacker news", "https://news.ycombinator.com",
            ; Swedish services
            "swish", "https://swish.nu",
            "bankid", "https://bankid.com",
            "1177", "https://1177.se",
            "skatteverket", "https://skatteverket.se",
            "postnord", "https://postnord.se",
            "systembolaget", "https://systembolaget.se",
            "hemnet", "https://hemnet.se",
            "eniro", "https://eniro.se",
            "hitta", "https://hitta.se",
            ; Gaming
            "steam", "https://store.steampowered.com",
            "epic games", "https://store.epicgames.com",
            "playstation", "https://store.playstation.com",
            "xbox", "https://xbox.com",
            "ign", "https://ign.com",
            ; Misc
            "canva", "https://canva.com",
            "dropbox", "https://dropbox.com",
            "outlook", "https://outlook.live.com",
            "hotmail", "https://outlook.live.com",
            "yahoo", "https://yahoo.com",
            "speedtest", "https://speedtest.net",
            "translate", "https://translate.google.com",
            "weather", "https://weather.com",
            "wolfram", "https://wolframalpha.com"
        )

        urlCmd := RegExReplace(urlCmd, "[.\s]+$", "")  ; Strip trailing dots/spaces
        if sites.Has(urlCmd) {
            Run(sites[urlCmd])
        } else if RegExMatch(urlCmd, "^([\w\-]+\.[\w\-]+(\.[\w\-]+)?(\/\S*)?)$", &urlMatch) {
            url := urlMatch[1]
            if !RegExMatch(url, "^https?://")
                url := "https://" url
            Run(url)
        } else {
            matched := false
            ToolTip('Unknown: "' text '"')
            SetTimer(() => ToolTip(), -2500)
        }
    }

    if matched {
        ToolTip("CMD: " text)
        SetTimer(() => ToolTip(), -1500)
    }
}
