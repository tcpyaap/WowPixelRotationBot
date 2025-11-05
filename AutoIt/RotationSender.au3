; ===================================================================
; ConRO Color Helper - Simplified and Optimized Version
; Monitors ConRO color pixels and sends corresponding keystrokes
;
; NOTE (behavior summary):
; - The numeric recommendations (0..35) and therefore the mapped actions/keys
;   are produced by the ConRO addon. This script DECODES ConRO's color pixels
;   back into numeric indices and treats those indices as action identifiers.
;   There is no direct GUI setting to change the underlying index->action
;   mapping because that mapping is controlled by ConRO and the in-game
;   `ConRO_Skills` addon.
;
; - What you CAN configure in this script's GUI:
;   * Enable/disable broad action categories (checkboxes): Interrupt, Purge,
;     Defense, Attack/Rotation. These control which ConRO-proposed actions
;     the sender is allowed to act upon (priority order applies).
;   * Timing / anti-detection parameters: reaction delay, random % for
;     reaction delay, keypress duration and its random %, and an absolute
;     minimum delay between keys (hard limit). These aim to simulate human
;     behavior but DO NOT guarantee evasion of detection systems.
;
; - Safety: Do NOT use this on Retail WoW. This project is for research/learning
;   and controlled testing only. Using automation on retail servers can lead to
;   account penalties.
; ===================================================================

#include <GUIConstantsEx.au3>
#include <Misc.au3>

; =========================== CONFIGURATION ===========================
Global Const $WOW_WINDOW_TITLE = "[TITLE:World of Warcraft]"
Global Const $SCAN_DELAY = 100 ; Main scanning delay in milliseconds
Global Const $COLOR_CHANGE_TIMEOUT = 2000 ; Time before allowing same color again
Global Const $KEY_REPEAT_TIMEOUT = 1500 ; Minimum time between same key presses

; Pixel positions for 5x5 squares (reading center pixel at position 2,2)
Global Const $PIXEL_POSITIONS[6][3] = [ _
    [0, 0, "ConROWindow"], _         ; Center of 5x5 square at (0,0)
    [0, 2, "ConROWindow2"], _        ; Center of 5x5 square at (0,-6)
    [0, 4, "ConRODefenseWindow"], _ ; Center of 5x5 square at (0,-12)
    [0, 6, "ConROInterruptWindow"], _ ; Center of 5x5 square at (0,-18)
    [0, 8, "ConROPurgeWindow"], _   ; Center of 5x5 square at (0,-24)
    [0, 10, "StatusFrame"] _         ; Center of 5x5 square at (0,-30)
]

; Color mapping (ConRO rotation value -> RGB hex -> Key)
; 0-9 keep the historical colors, 10-35 map to virtual keys A-Z.
Global Const $COLOR_MAP[36][2] = [ _
    ["FF0000", "0"], _ ; Red -> 0
    ["00FF00", "1"], _ ; Green -> 1
    ["0000FF", "2"], _ ; Blue -> 2
    ["FFFF00", "3"], _ ; Yellow -> 3
    ["FF00FF", "4"], _ ; Magenta -> 4
    ["00FFFF", "5"], _ ; Cyan -> 5
    ["808080", "6"], _ ; Gray -> 6
    ["FF8000", "7"], _ ; Orange -> 7
    ["00FF80", "8"], _ ; Turquoise -> 8
    ["8000FF", "9"], _ ; Purple -> 9
    ["6926FF", "A"], _ ; Violet Blue -> A
    ["26FF2A", "B"], _ ; Bright Green -> B
    ["FF2662", "C"], _ ; Cerise -> C
    ["26A1FF", "D"], _ ; Azure -> D
    ["E0FF26", "E"], _ ; Lime Yellow -> E
    ["DE26FF", "F"], _ ; Vivid Violet -> F
    ["26FF9F", "G"], _ ; Spring Green -> G
    ["FF6026", "H"], _ ; Orange Red -> H
    ["262CFF", "I"], _ ; Indigo -> I
    ["6BFF26", "J"], _ ; Lime Punch -> J
    ["FF26AA", "K"], _ ; Hot Pink -> K
    ["26EAFF", "L"], _ ; Capri -> L
    ["FFD526", "M"], _ ; Amber -> M
    ["9626FF", "N"], _ ; Electric Purple -> N
    ["26FF57", "O"], _ ; Emerald -> O
    ["FF2635", "P"], _ ; Fiery Red -> P
    ["2674FF", "Q"], _ ; Royal Blue -> Q
    ["B4FF26", "R"], _ ; Chartreuse -> R
    ["FF26F3", "S"], _ ; Fuchsia -> S
    ["26FFCC", "T"], _ ; Aquamarine -> T
    ["FF8D26", "U"], _ ; Tangerine -> U
    ["4D26FF", "V"], _ ; Electric Indigo -> V
    ["3EFF26", "W"], _ ; Neon Green -> W
    ["FF267E", "X"], _ ; Wild Strawberry -> X
    ["26BDFF", "Y"], _ ; Vivid Sky Blue -> Y
    ["FCFF26", "Z"]   ; Lemon -> Z
]

; Status frame color mapping (from ConRO_Port.lua)
Global Const $STATUS_COLOR_MAP[4][2] = [ _
    ["000000", "IDLE"], _    ; Black -> Idle
    ["FF0000", "CAST"], _    ; Red -> Casting
    ["FF8000", "CHAN"], _    ; Orange -> Channeling  
    ["FFFFFF", "GCD"] _      ; White -> Global Cooldown
]

; =========================== GLOBAL VARIABLES ===========================
Global $g_bPaused = True
Global $g_hGUI
Global $g_sLastDetectedKey = ""
Global $g_iLastUpdate = 0

; GUI Controls
Global $g_lblStatus, $g_lblIndicator, $g_lblCurrentColor, $g_lblLastKey
Global $g_btnToggle, $g_btnExit
Global $g_lblPixels[6][2] ; [index][0=color_square, 1=info_text]
Global $g_lblProposedKey ; Large display for proposed key
Global $g_editKeyLog, $g_btnClearLog ; Key log controls
Global $g_lblBlockReason ; Diagnostic label for why key is blocked

; Action type checkboxes
Global $g_chkInterrupt, $g_chkPurge, $g_chkDefense, $g_chkAttack

; Delay controls
Global $g_sliderSendDelay, $g_lblSendDelayValue, $g_sliderSendRandom
Global $g_sliderKeypressDelay, $g_lblKeypressDelayValue, $g_sliderKeypressRandom
Global $g_sliderAbsoluteMin, $g_lblAbsoluteMinValue
Global $g_iLastSendTime = 0
Global $g_sPendingKey = "" ; Key waiting to be sent after hard limit

; =========================== INITIALIZATION ===========================
HotKeySet("²", "_TogglePause")
_CreateGUI()
MainLoop()


; =========================== GUI CREATION ===========================
Func _CreateGUI()
    $g_hGUI = GUICreate("ConRO Color Helper - Smart Priority", 1050, 550)
    
    ; Status and control section (top)
    GUICtrlCreateLabel("Status:", 10, 10, 50, 20)
    $g_lblStatus = GUICtrlCreateLabel("Paused", 70, 10, 60, 20)
    $g_lblIndicator = GUICtrlCreateLabel("●", 140, 5, 30, 30)
    GUICtrlSetFont($g_lblIndicator, 20, 800)
    GUICtrlSetColor($g_lblIndicator, 0xFF0000) ; Red for paused
    
    ; Control buttons
    $g_btnToggle = GUICtrlCreateButton("Start/Pause (²)", 200, 10, 100, 30)
    $g_btnExit = GUICtrlCreateButton("Exit", 310, 10, 60, 30)
    
    ; LARGE PROPOSED KEY DISPLAY
    GUICtrlCreateGroup("Proposed Key", 400, 5, 320, 80)
    $g_lblProposedKey = GUICtrlCreateLabel("-", 420, 20, 280, 45)
    GUICtrlSetFont($g_lblProposedKey, 36, 800, 0, "Arial")
    GUICtrlSetColor($g_lblProposedKey, 0x0000FF) ; Blue color
    $g_lblBlockReason = GUICtrlCreateLabel("", 420, 65, 280, 15)
    GUICtrlSetFont($g_lblBlockReason, 7, 400, 0, "Arial")
    GUICtrlSetColor($g_lblBlockReason, 0xFF0000) ; Red for warnings
    GUICtrlCreateGroup("", -99, -99, 1, 1)
    
    ; Pixel monitoring section (left side)
    GUICtrlCreateGroup("ConRO Pixel Monitor", 10, 100, 350, 280)
    _CreatePixelLabels()
    GUICtrlCreateGroup("", -99, -99, 1, 1)
    
    ; Action type controls (right side)
    GUICtrlCreateGroup("Action Types (Priority Order)", 380, 100, 340, 150)
    $g_chkInterrupt = GUICtrlCreateCheckbox("1. Enable Interrupt (Highest)", 390, 125, 200, 20)
    GUICtrlSetState($g_chkInterrupt, $GUI_CHECKED)
    GUICtrlSetFont($g_chkInterrupt, 9, 600)
    
    $g_chkPurge = GUICtrlCreateCheckbox("2. Enable Purge/Dispel", 390, 150, 200, 20)
    GUICtrlSetState($g_chkPurge, $GUI_CHECKED)
    GUICtrlSetFont($g_chkPurge, 9, 600)
    
    $g_chkDefense = GUICtrlCreateCheckbox("3. Enable Defense", 390, 175, 200, 20)
    GUICtrlSetState($g_chkDefense, $GUI_CHECKED)
    GUICtrlSetFont($g_chkDefense, 9, 600)
    
    $g_chkAttack = GUICtrlCreateCheckbox("4. Enable Attack/Rotation (Lowest)", 390, 200, 200, 20)
    GUICtrlSetState($g_chkAttack, $GUI_CHECKED)
    GUICtrlSetFont($g_chkAttack, 9, 600)
    
    GUICtrlCreateLabel("Note: ConROWindow2 is never used", 390, 220, 200, 20)
    GUICtrlCreateGroup("", -99, -99, 1, 1)
    
    ; Status info section
    GUICtrlCreateGroup("Player Status", 380, 270, 340, 50)
    GUICtrlCreateLabel("Blocked: GCD/CAST/CHAN | Active: IDLE only", 390, 290, 250, 15)
    GUICtrlSetFont(GUICtrlCreateLabel("² = Toggle", 550, 300, 80, 15), 9, 600)
    GUICtrlCreateGroup("", -99, -99, 1, 1)
    
    ; Delay settings section
    GUICtrlCreateGroup("Delay Settings", 380, 330, 340, 180)
    
    ; Send delay (reaction time simulation)
    GUICtrlCreateLabel("Reaction delay (before send):", 390, 350, 130, 15)
    $g_sliderSendDelay = GUICtrlCreateSlider(390, 365, 150, 20)
    GUICtrlSetLimit($g_sliderSendDelay, 500, 0)
    GUICtrlSetData($g_sliderSendDelay, 100)
    $g_lblSendDelayValue = GUICtrlCreateLabel("100ms", 550, 365, 60, 15)
    
    GUICtrlCreateLabel("Random %:", 390, 385, 60, 15)
    $g_sliderSendRandom = GUICtrlCreateSlider(450, 385, 90, 20)
    GUICtrlSetLimit($g_sliderSendRandom, 50, 0)
    GUICtrlSetData($g_sliderSendRandom, 20)
    GUICtrlCreateLabel("±20%", 550, 385, 50, 15)
    
    ; Keypress delay (between down and up)
    GUICtrlCreateLabel("Keypress duration:", 390, 410, 100, 15)
    $g_sliderKeypressDelay = GUICtrlCreateSlider(390, 425, 150, 20)
    GUICtrlSetLimit($g_sliderKeypressDelay, 200, 10)
    GUICtrlSetData($g_sliderKeypressDelay, 60)
    $g_lblKeypressDelayValue = GUICtrlCreateLabel("60ms", 550, 425, 50, 15)
    
    GUICtrlCreateLabel("Random %:", 390, 445, 60, 15)
    $g_sliderKeypressRandom = GUICtrlCreateSlider(450, 445, 90, 20)
    GUICtrlSetLimit($g_sliderKeypressRandom, 50, 0)
    GUICtrlSetData($g_sliderKeypressRandom, 10)
    GUICtrlCreateLabel("±10%", 550, 445, 50, 15)
    
    ; Absolute minimum delay between keys
    GUICtrlCreateLabel("Absolute min between keys:", 390, 470, 130, 15)
    $g_sliderAbsoluteMin = GUICtrlCreateSlider(390, 485, 150, 20)
    GUICtrlSetLimit($g_sliderAbsoluteMin, 1000, 0)
    GUICtrlSetData($g_sliderAbsoluteMin, 300)
    $g_lblAbsoluteMinValue = GUICtrlCreateLabel("300ms", 550, 485, 50, 15)
    GUICtrlSetFont(GUICtrlCreateLabel("(Hard limit)", 640, 485, 70, 15), 8, 400)
    
    GUICtrlCreateGroup("", -99, -99, 1, 1)
    
    ; Key Log section (right side)
    GUICtrlCreateGroup("Key Log (Last 50 keys)", 740, 100, 290, 410)
    $g_editKeyLog = GUICtrlCreateEdit("", 750, 120, 270, 360, 0x0804) ; ES_MULTILINE + ES_READONLY + ES_AUTOVSCROLL
    GUICtrlSetFont($g_editKeyLog, 8, 400, 0, "Consolas")
    $g_btnClearLog = GUICtrlCreateButton("Clear Log", 750, 485, 80, 25)
    GUICtrlCreateGroup("", -99, -99, 1, 1)
    
    GUISetState(@SW_SHOW)
EndFunc

; Create labels for each pixel monitoring
Func _CreatePixelLabels()
    Local $iStartY = 125
    Local $iLineHeight = 40
    
    For $i = 0 To 5
        Local $iY = $iStartY + ($i * $iLineHeight)
        
        ; Pixel name
        GUICtrlCreateLabel($PIXEL_POSITIONS[$i][2] & ":", 20, $iY, 120, 15)
        
        ; Color square indicator
        $g_lblPixels[$i][0] = GUICtrlCreateLabel("■", 20, $iY + 18, 15, 15)
        GUICtrlSetFont($g_lblPixels[$i][0], 12, 800)
        GUICtrlSetColor($g_lblPixels[$i][0], 0x000000)
        
        ; Color info text
        $g_lblPixels[$i][1] = GUICtrlCreateLabel("000000 | -", 40, $iY + 18, 120, 15)
        GUICtrlSetFont($g_lblPixels[$i][1], 8, 400, 0, "Consolas")
    Next
EndFunc






; =========================== MAIN LOOP ===========================
Func MainLoop()
	While 1
		_CheckGUIEvents()

		If WinActive($WOW_WINDOW_TITLE) Then
			_MonitorPixels()
		EndIf

		Sleep(10) ; Minimal sleep for CPU usage
	WEnd
EndFunc


; =========================== GUI EVENT HANDLING ===========================
Func _CheckGUIEvents()
    Local $msg = GUIGetMsg()
    Switch $msg
        Case $GUI_EVENT_CLOSE
            _Exit()
        Case $g_btnToggle
            _TogglePause()
        Case $g_btnExit
            _Exit()
        Case $g_sliderSendDelay
            GUICtrlSetData($g_lblSendDelayValue, GUICtrlRead($g_sliderSendDelay) & "ms")
        Case $g_sliderSendRandom
            GUICtrlSetData($g_lblSendDelayValue, GUICtrlRead($g_sliderSendDelay) & "ms")
        Case $g_sliderKeypressDelay
            GUICtrlSetData($g_lblKeypressDelayValue, GUICtrlRead($g_sliderKeypressDelay) & "ms")
        Case $g_sliderKeypressRandom
            GUICtrlSetData($g_lblKeypressDelayValue, GUICtrlRead($g_sliderKeypressDelay) & "ms")
        Case $g_sliderAbsoluteMin
            GUICtrlSetData($g_lblAbsoluteMinValue, GUICtrlRead($g_sliderAbsoluteMin) & "ms")
        Case $g_btnClearLog
            GUICtrlSetData($g_editKeyLog, "")
    EndSwitch
EndFunc


; =========================== CORE LOGIC ===========================
; Main pixel monitoring and key sending function
Func _MonitorPixels()
    Local $aPixelColors[6]
    Local $bShouldSendKey = False
    
    ; Read all pixel colors first
    For $i = 0 To 5
        $aPixelColors[$i] = PixelGetColor($PIXEL_POSITIONS[$i][0], $PIXEL_POSITIONS[$i][1])
        ; Update display (always active)
        _UpdatePixelDisplay($i, $aPixelColors[$i])
    Next
    
    ; State machine for key determination
    Local $sKeyToSend = _DetermineKeyToSend($aPixelColors)
    
    ; Always update the proposed key display
    If $sKeyToSend <> "" Then
        GUICtrlSetData($g_lblProposedKey, $sKeyToSend)
        GUICtrlSetColor($g_lblProposedKey, 0x0000FF) ; Blue for valid key
    Else
        GUICtrlSetData($g_lblProposedKey, "-")
        GUICtrlSetColor($g_lblProposedKey, 0x808080) ; Gray for no key
    EndIf
    
    ; Clear diagnostic by default
    GUICtrlSetData($g_lblBlockReason, "")
    
    ; Check if WoW is active
    If Not WinActive($WOW_WINDOW_TITLE) Then
        GUICtrlSetData($g_lblBlockReason, "⚠ WoW window not active")
        GUICtrlSetColor($g_lblProposedKey, 0xFF8000) ; Orange
        Sleep(5)
        Return
    EndIf
    
    ; Send key only if not paused
    If Not $g_bPaused Then
        Local $iAbsoluteMin = GUICtrlRead($g_sliderAbsoluteMin)
        Local $iTimeSinceLastSend = ($g_iLastSendTime = 0 ? 99999 : TimerDiff($g_iLastSendTime))
        
        ; Priority 1: Check if we have a pending key waiting for hard limit
        If $g_sPendingKey <> "" Then
            If $iTimeSinceLastSend >= $iAbsoluteMin Then
                ; Hard limit passed, send pending key NOW
                Local $bSent = _SendKeyDLL($g_sPendingKey)
                If $bSent Then
                    $g_sLastDetectedKey = $g_sPendingKey
                    $g_sPendingKey = ""
                    $bShouldSendKey = True
                EndIf
            Else
                ; Still waiting for hard limit
                Local $iRemaining = Int($iAbsoluteMin - $iTimeSinceLastSend)
                GUICtrlSetData($g_lblBlockReason, "⏱ Pending: " & $g_sPendingKey & " (wait " & $iRemaining & "ms)")
                GUICtrlSetColor($g_lblProposedKey, 0xFFFF00) ; Yellow for pending
            EndIf
        EndIf
        
        ; Priority 2: New key proposed
        If $sKeyToSend <> "" And $g_sPendingKey = "" Then
            ; Check if we can send immediately
            If $iTimeSinceLastSend >= $iAbsoluteMin Then
                ; Hard limit OK, send immediately
                $g_sLastDetectedKey = $sKeyToSend
                Local $bSent = _SendKeyDLL($sKeyToSend)
                If $bSent Then
                    $bShouldSendKey = True
                EndIf
            Else
                ; Hard limit not reached, mark as pending
                $g_sPendingKey = $sKeyToSend
                Local $iRemaining = Int($iAbsoluteMin - $iTimeSinceLastSend)
                GUICtrlSetData($g_lblBlockReason, "⏱ Hard limit: wait " & $iRemaining & "ms")
                GUICtrlSetColor($g_lblProposedKey, 0xFFFF00) ; Yellow for pending
            EndIf
        EndIf
    Else
        ; If paused, clear any pending key
        If $g_sPendingKey <> "" Then
            $g_sPendingKey = ""
        EndIf
        GUICtrlSetData($g_lblBlockReason, "⏸ Paused (press ²)")
    EndIf
    
    ; Small delay to prevent excessive CPU usage
    If Not $bShouldSendKey Then Sleep(5)
EndFunc

; State machine to determine which key to send based on priority system
Func _DetermineKeyToSend($aPixelColors)
    ; Frame indices:
    ; 0 = ConROWindow
    ; 1 = ConROWindow2 (never used per requirements)
    ; 2 = ConRODefenseWindow
    ; 3 = ConROInterruptWindow  
    ; 4 = ConROPurgeWindow
    ; 5 = StatusFrame
    
    ; Step 1: Check StatusFrame - if busy, don't send any key
    Local $sStatus = _GetStatusForColor($aPixelColors[5])
    If $sStatus = "GCD" Or $sStatus = "CAST" Or $sStatus = "CHAN" Then
        Return "" ; Player is busy, don't send key
    EndIf
    
    ; Step 2: Only proceed if StatusFrame shows IDLE
    If $sStatus <> "IDLE" Then
        Return "" ; Unknown status, be safe and don't send
    EndIf
    
    ; Step 3: Check if ConROWindow (index 0) shows WHITE - if yes, no key at all
    Local $sConROWindowColor = StringUpper(Hex($aPixelColors[0], 6))
    If $sConROWindowColor = "FFFFFF" Then
        Return "" ; ConROWindow shows white (IDLE), don't send any key
    EndIf
    
    ; Step 4: Priority-based key determination (IDLE state and ConROWindow not white)
    ; Priority 1: InterruptWindow (highest priority)
    If BitAND(GUICtrlRead($g_chkInterrupt), $GUI_CHECKED) Then
        Local $sKey = _GetKeyForColor($aPixelColors[3])
        If $sKey <> "" Then
            Return $sKey
        EndIf
    EndIf
    
    ; Priority 2: PurgeWindow
    If BitAND(GUICtrlRead($g_chkPurge), $GUI_CHECKED) Then
        Local $sKey = _GetKeyForColor($aPixelColors[4])
        If $sKey <> "" Then
            Return $sKey
        EndIf
    EndIf
    
    ; Priority 3: DefenseWindow
    If BitAND(GUICtrlRead($g_chkDefense), $GUI_CHECKED) Then
        Local $sKey = _GetKeyForColor($aPixelColors[2])
        If $sKey <> "" Then
            Return $sKey
        EndIf
    EndIf
    
    ; Priority 4: ConROWindow (lowest priority, never ConROWindow2)
    If BitAND(GUICtrlRead($g_chkAttack), $GUI_CHECKED) Then
        Local $sKey = _GetKeyForColor($aPixelColors[0])
        If $sKey <> "" Then
            Return $sKey
        EndIf
    EndIf
    
    ; No valid key found
    Return ""
EndFunc

; Update pixel display in GUI
Func _UpdatePixelDisplay($iIndex, $iColor)
    Local $sHexColor = Hex($iColor, 6)
    Local $sDisplayValue = ""
    
    ; Different handling for StatusFrame (index 5) vs rotation frames (0-4)
    If $iIndex = 5 Then
        ; StatusFrame - show status description
        $sDisplayValue = _GetStatusForColor($iColor)
    Else
        ; Rotation frames - show key mapping
        Local $sKey = _GetKeyForColor($iColor)
        $sDisplayValue = ($sKey = "" ? "-" : $sKey)
    EndIf
    
    ; Update color square
    GUICtrlSetColor($g_lblPixels[$iIndex][0], $iColor)
    
    ; Update info text
    Local $sInfo = $sHexColor & " | " & $sDisplayValue
    GUICtrlSetData($g_lblPixels[$iIndex][1], $sInfo)
EndFunc

; Get key for color from mapping
Func _GetKeyForColor($iColor)
    Local $sHexColor = StringUpper(Hex($iColor, 6))
    
    For $i = 0 To UBound($COLOR_MAP) - 1
        If $COLOR_MAP[$i][0] = $sHexColor Then
            Return $COLOR_MAP[$i][1]
        EndIf
    Next
    
    Return "" ; No matching key found
EndFunc

; Get status description for color (for StatusFrame)
Func _GetStatusForColor($iColor)
    Local $sHexColor = StringUpper(Hex($iColor, 6))
    
    For $i = 0 To UBound($STATUS_COLOR_MAP) - 1
        If $STATUS_COLOR_MAP[$i][0] = $sHexColor Then
            Return $STATUS_COLOR_MAP[$i][1]
        EndIf
    Next
    
    Return "UNK" ; Unknown status
EndFunc





; =========================== UTILITY FUNCTIONS ===========================
; Toggle pause state
Func _TogglePause()
    $g_bPaused = Not $g_bPaused
    If $g_bPaused Then
        GUICtrlSetData($g_lblStatus, "Paused")
        GUICtrlSetColor($g_lblIndicator, 0xFF0000) ; Red
    Else
        GUICtrlSetData($g_lblStatus, "Active")
        GUICtrlSetColor($g_lblIndicator, 0x00FF00) ; Green
    EndIf
EndFunc




; Send key using DLL method for WoW
Func _SendKeyDLL($sKey)
    If Not WinActive($WOW_WINDOW_TITLE) Then Return False
    
    ; Note: Hard limit check is done BEFORE calling this function
    ; This function assumes it's safe to send the key
    
    ; Apply reaction delay (time between detection and key send)
    Local $iSendDelay = GUICtrlRead($g_sliderSendDelay)
    Local $iSendRandom = GUICtrlRead($g_sliderSendRandom)
    Local $iActualReactionDelay = _ApplyRandomDelay($iSendDelay, $iSendRandom)
    
    If $iActualReactionDelay > 0 Then
        Sleep($iActualReactionDelay)
    EndIf
    
    ; Convert key to virtual key code
    Local $iVirtualKey
    $sKey = StringUpper($sKey)

    Switch $sKey
        Case "0" To "9", "A" To "Z"
            $iVirtualKey = Asc($sKey)
        Case Else
            Return False ; Unsupported key
    EndSwitch
    
    ; Calculate keypress duration with random variation
    Local $iKeypressDelay = GUICtrlRead($g_sliderKeypressDelay)
    Local $iKeypressRandom = GUICtrlRead($g_sliderKeypressRandom)
    Local $iActualKeypressDelay = _ApplyRandomDelay($iKeypressDelay, $iKeypressRandom)
    
    ; Send key using user32.dll
    DllCall("user32.dll", "short", "VkKeyScanA", "char", Asc($sKey))
    DllCall("user32.dll", "none", "keybd_event", "byte", $iVirtualKey, "byte", 0, "dword", 0, "ulong_ptr", 0)
    Sleep($iActualKeypressDelay)
    DllCall("user32.dll", "none", "keybd_event", "byte", $iVirtualKey, "byte", 0, "dword", 2, "ulong_ptr", 0) ; Key up
    
    ; Log the key that was sent
    _LogKey($sKey)
    
    ; Update last send time
    $g_iLastSendTime = TimerInit()
    Return True ; Key was sent successfully
EndFunc

; Apply random percentage variation to a delay value
Func _ApplyRandomDelay($iBaseDelay, $iRandomPercent)
    If $iRandomPercent = 0 Then Return $iBaseDelay
    
    Local $iVariation = Int($iBaseDelay * $iRandomPercent / 100)
    Local $iMin = $iBaseDelay - $iVariation
    Local $iMax = $iBaseDelay + $iVariation
    
    Return Random($iMin, $iMax, 1)
EndFunc

; Add key to log with timestamp
Func _LogKey($sKey)
    Local $sTimestamp = @HOUR & ":" & @MIN & ":" & @SEC & "." & StringFormat("%03d", @MSEC)
    Local $sLogEntry = $sTimestamp & " > " & $sKey & @CRLF
    
    ; Get current log content
    Local $sCurrentLog = GUICtrlRead($g_editKeyLog)
    
    ; Add new entry at the top
    Local $sNewLog = $sLogEntry & $sCurrentLog
    
    ; Keep only last 50 lines
    Local $aLines = StringSplit($sNewLog, @CRLF, 1)
    If $aLines[0] > 50 Then
        $sNewLog = ""
        For $i = 1 To 50
            $sNewLog &= $aLines[$i] & @CRLF
        Next
    EndIf
    
    ; Update log display
    GUICtrlSetData($g_editKeyLog, $sNewLog)
EndFunc

; Exit function
Func _Exit()
    Exit
EndFunc

