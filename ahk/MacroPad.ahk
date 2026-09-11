#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
; MacroPad Multi-App Multi-Device Remapper
; ============================================================================

#Include Lib\AutoHotInterception.ahk
#Include JSON.ahk

Persistent()

global ConfigPath   := A_ScriptDir "\config.json"
global AHI          := AutoHotInterception()
global Config       := ""
global TargetVID    := 0
global TargetPID    := 0
global MatrixOrder  := ["71","72","73","74","75","76","77","78","79","80","81","309","82","55","83","284"]
global g_EditApp    := ""
global g_EditDevice := ""

global ShortNames := Map(
    "previous_photo","Prev","next_photo","Next","grid_view","Grid(G)","focus_view","Focus(D)",
    "detail_view","Detail(D)","reject","Reject(X)","pick","Pick(Z)","unflag","Unflag(U)",
    "undo","Undo","redo","Redo","crop","Crop(C)","remove_tool","Remove",
    "auto_tone","AutoTone","white_balance_picker","WB Pick","copy_settings","Copy",
    "paste_settings","Paste","tab_next","Tab->","tab_prev","<-Tab","f6_cycle","F6",
    "shift_f6_cycle","Sh+F6","exposure_up","Exp+","exposure_down","Exp-","activate_control","Space"
)

; ---- Load config ------------------------------------------------------------
if !FileExist(ConfigPath) {
    MsgBox("config.json not found:`n" ConfigPath, "MacroPad", "Iconx")
    ExitApp()
}
try {
    Config := JSON.parse(FileRead(ConfigPath))
} catch as e {
    MsgBox("config.json parse error: " e.Message, "MacroPad", "Iconx")
    ExitApp()
}

try {
    activeDev := Config["devices"][Config["active_device"]]
    TargetVID := Integer("0x" activeDev["vid"])
    TargetPID := Integer("0x" activeDev["pid"])
} catch {
    MsgBox("Active device '" Config["active_device"] "' not found in devices list.", "MacroPad", "Iconx")
    ExitApp()
}

; ---- Tray ------------------------------------------------------------------
A_TrayMenu.Delete()
A_TrayMenu.Add("MacroPad Remapper", (*) => "")
A_TrayMenu.Disable("MacroPad Remapper")
A_TrayMenu.Add()
A_TrayMenu.Add("App-specific mode", ToggleAppSpecific)
if Config["settings"]["app_specific_mode"]
    A_TrayMenu.Check("App-specific mode")
A_TrayMenu.Add("Edit mapping", (*) => ShowRemapGui())
A_TrayMenu.Add("Reload config", (*) => Reload())
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())

ToggleAppSpecific(*) {
    global Config
    Config["settings"]["app_specific_mode"] := !Config["settings"]["app_specific_mode"]
    if Config["settings"]["app_specific_mode"]
        A_TrayMenu.Check("App-specific mode")
    else
        A_TrayMenu.Uncheck("App-specific mode")
}

; ---- Subscribe to device ---------------------------------------------------
SubscribedAny := false
startLog := FormatTime(, "HH:mm:ss") " --- startup VID=" Format("{:04X}", TargetVID) " PID=" Format("{:04X}", TargetPID) " ---`n"
for id, dev in AHI.GetDeviceList() {
    if (dev.VID = TargetVID && dev.PID = TargetPID && !dev.IsMouse) {
        AHI.SubscribeKeyboard(id, Config["settings"]["block_original_input"], KeyEvent.Bind(id))
        SubscribedAny := true
        startLog .= "  subscribed ID=" id "`n"
    }
}
try FileAppend(startLog, A_ScriptDir "\debug.log")
if !SubscribedAny {
    MsgBox("No Interception keyboard device found for VID_" Format("{:04X}", TargetVID) " PID_" Format("{:04X}", TargetPID), "MacroPad", "Iconx")
    ExitApp()
}

; ---- Right encoder (Volume hotkeys - not device-specific) ------------------
Hotkey("Volume_Down", (*) => HandleRightEncoder("cw",    "Volume_Down"))
Hotkey("Volume_Up",   (*) => HandleRightEncoder("ccw",   "Volume_Up"))
Hotkey("Volume_Mute", (*) => HandleRightEncoder("press", "Volume_Mute"))

TrayTip("MacroPad Remapper", "Active - " activeDev["label"] ". Right-click to edit mapping.")
return

; ============================================================================
; CORE ROUTING
; ============================================================================

GetActiveApp() {
    global Config
    for appKey, profile in Config["apps"] {
        if WinActive("ahk_exe " profile["process"])
            return appKey
    }
    return ""
}

KeyEvent(id, code, state) {
    try {
        KeyEventInner(code, state)
    } catch as e {
        MsgBox("KeyEvent error: " e.Message "`nCode=" code, "MacroPad - ERROR", "Iconx")
    }
}

KeyEventInner(code, state) {
    global Config
    if state = 0
        return
    appKey := GetActiveApp()
    if Config["settings"]["app_specific_mode"] && appKey = ""
        return
    if appKey = ""
        return
    profile := Config["apps"][appKey]
    codeStr := String(code)
    if !profile["keys"].Has(codeStr)
        return
    entry := profile["keys"][codeStr]
    ; Direct binding takes priority over named action
    if entry.Has("keys") && entry["keys"] != "" {
        try FileAppend(FormatTime(, "HH:mm:ss") " app=" appKey " code=" codeStr " -> direct:" entry["keys"] "`n", A_ScriptDir "\debug.log")
        SendInput("{Blind}" entry["keys"])
        return
    }
    actionName := entry["action"]
    if actionName = ""
        return
    try FileAppend(FormatTime(, "HH:mm:ss") " app=" appKey " code=" codeStr " -> " actionName "`n", A_ScriptDir "\debug.log")
    PerformAction(actionName, profile["actions"])
}

HandleRightEncoder(dir, nativeKeyName) {
    try {
        HandleRightEncoderInner(dir, nativeKeyName)
    } catch as e {
        MsgBox("RightEncoder error: " e.Message, "MacroPad - ERROR", "Iconx")
    }
}

HandleRightEncoderInner(dir, nativeKeyName) {
    global Config
    appKey := GetActiveApp()
    if appKey = "" {
        SendInput("{Blind}{" nativeKeyName "}")
        return
    }
    profile := Config["apps"][appKey]
    if !profile["right_encoder"].Has(dir)
        return
    entry := profile["right_encoder"][dir]
    if entry.Has("keys") && entry["keys"] != "" {
        SendInput("{Blind}" entry["keys"])
        return
    }
    actionName := entry["action"]
    if actionName = ""
        return
    PerformAction(actionName, profile["actions"])
}

PerformAction(actionName, actionsMap) {
    if !actionsMap.Has(actionName)
        return
    action := actionsMap[actionName]
    if !action["supported"] {
        TrayTip("Not supported", actionName " has no confirmed shortcut.", 1)
        return
    }
    try FileAppend(FormatTime(, "HH:mm:ss") "   -> [" action["keys"] "]`n", A_ScriptDir "\debug.log")
    SendInput("{Blind}" action["keys"])
}

; ============================================================================
; PRESET LIBRARY
; ============================================================================

BuildKeyMap(codes, actions) {
    labels := Map("71","7","72","8","73","9","74","-","75","4","76","5","77","6","78","+",
                  "79","1","80","2","81","3","309","/","82","0","55","*","83",".","284","Enter")
    m := Map()
    for code in codes {
        lbl := labels.Has(code) ? labels[code] : code
        act := actions.Has(code) ? actions[code] : ""
        m[code] := Map("label", lbl, "action", act)
    }
    return m
}

BuildEncoder(ccw, press, cw) {
    return Map(
        "cw",    Map("label","LeftEncoder-CW",    "action", cw),
        "ccw",   Map("label","LeftEncoder-CCW",   "action", ccw),
        "press", Map("label","LeftEncoder-Press", "action", press)
    )
}

BuildREncoder(ccw, press, cw) {
    return Map(
        "cw",    Map("label","RightEncoder-CW",    "action", cw),
        "ccw",   Map("label","RightEncoder-CCW",   "action", ccw),
        "press", Map("label","RightEncoder-Press", "action", press)
    )
}

BuildPresets() {
    p := Map()

    ; Shared action tables
    lrActions := Map(
        "previous_photo",       Map("keys","{Left}",  "supported",true),
        "next_photo",           Map("keys","{Right}", "supported",true),
        "grid_view",            Map("keys","g",       "supported",true),
        "detail_view",          Map("keys","d",       "supported",true),
        "reject",               Map("keys","x",       "supported",true),
        "pick",                 Map("keys","z",       "supported",true),
        "unflag",               Map("keys","u",       "supported",true),
        "undo",                 Map("keys","^z",      "supported",true),
        "redo",                 Map("keys","+^z",     "supported",true),
        "crop",                 Map("keys","c",       "supported",true),
        "remove_tool",          Map("keys","+t",      "supported",true),
        "auto_tone",            Map("keys","+a",      "supported",true),
        "white_balance_picker", Map("keys","w",       "supported",true),
        "copy_settings",        Map("keys","^c",      "supported",true),
        "paste_settings",       Map("keys","^v",      "supported",true),
        "tab_next",             Map("keys","{Tab}",   "supported",true),
        "tab_prev",             Map("keys","+{Tab}",  "supported",true),
        "f6_cycle",             Map("keys","{F6}",    "supported",true),
        "shift_f6_cycle",       Map("keys","+{F6}",   "supported",true),
        "exposure_up",          Map("keys","{Right}", "supported",true),
        "exposure_down",        Map("keys","{Left}",  "supported",true),
        "activate_control",     Map("keys","{Space}", "supported",true)
    )

    lrKeyActions := Map("71","previous_photo","72","next_photo","73","grid_view","74","reject",
        "75","unflag","76","pick","77","detail_view","78","shift_f6_cycle","79","undo","80","redo",
        "81","crop","309","remove_tool","82","auto_tone","55","white_balance_picker",
        "83","copy_settings","284","paste_settings")

    p["lightroom_full"] := Map("label","Lightroom Desktop (full)","process","lightroom.exe",
        "keys",        BuildKeyMap(["71","72","73","74","75","76","77","78","79","80","81","309","82","55","83","284"], lrKeyActions),
        "left_encoder",BuildEncoder("tab_prev","f6_cycle","tab_next"),
        "right_encoder",BuildREncoder("exposure_down","activate_control","exposure_up"),
        "actions",     lrActions)

    pxActions := Map(
        "previous_photo", Map("keys","{Left}",  "supported",true),
        "next_photo",     Map("keys","{Right}", "supported",true),
        "grid_view",      Map("keys","g",       "supported",true),
        "focus_view",     Map("keys","d",       "supported",true),
        "undo",           Map("keys","^z",      "supported",true),
        "redo",           Map("keys","+^z",     "supported",true),
        "tab_next",       Map("keys","{Tab}",   "supported",true),
        "tab_prev",       Map("keys","+{Tab}",  "supported",true)
    )
    pxKeyActions := Map("71","previous_photo","72","next_photo","73","grid_view","76","focus_view","79","undo","80","redo")

    p["pixieset"] := Map("label","Pixieset Photo Editor","process","PixiesetPhotoEditor.exe",
        "keys",        BuildKeyMap(["71","72","73","74","75","76","77","78","79","80","81","309","82","55","83","284"], pxKeyActions),
        "left_encoder",BuildEncoder("previous_photo","","next_photo"),
        "right_encoder",BuildREncoder("","",""),
        "actions",     pxActions)

    navActions := Map(
        "previous_photo", Map("keys","{Left}",  "supported",true),
        "next_photo",     Map("keys","{Right}", "supported",true),
        "grid_view",      Map("keys","g",       "supported",true),
        "focus_view",     Map("keys","d",       "supported",true),
        "reject",         Map("keys","x",       "supported",true),
        "pick",           Map("keys","p",       "supported",true),
        "unflag",         Map("keys","u",       "supported",true),
        "undo",           Map("keys","^z",      "supported",true),
        "redo",           Map("keys","+^z",     "supported",true)
    )
    navKeyActions := Map("71","previous_photo","72","next_photo","73","grid_view","74","reject",
        "75","unflag","76","pick","77","focus_view","79","undo","80","redo")

    p["navigation"] := Map("label","Navigation only (generic)","process","",
        "keys",        BuildKeyMap(["71","72","73","74","75","76","77","78","79","80","81","309","82","55","83","284"], navKeyActions),
        "left_encoder",BuildEncoder("previous_photo","grid_view","next_photo"),
        "right_encoder",BuildREncoder("","",""),
        "actions",     navActions)

    blankKeyActions := Map()
    p["blank"] := Map("label","Blank (all unmapped)","process","",
        "keys",        BuildKeyMap(["71","72","73","74","75","76","77","78","79","80","81","309","82","55","83","284"], blankKeyActions),
        "left_encoder",BuildEncoder("","",""),
        "right_encoder",BuildREncoder("","",""),
        "actions",     Map())

    return p
}

; ============================================================================
; REMAPPER GUI
; ============================================================================

ShowRemapGui(*) {
    global Config, MatrixOrder, g_EditApp, g_EditDevice, AHI

    ; Build device list
    devKeys := [], devLabels := []
    for dk, dv in Config["devices"] {
        devKeys.Push(dk)
        devLabels.Push(dv["label"] "  (VID " dv["vid"] " / PID " dv["pid"] ")")
    }
    for id, dev in AHI.GetDeviceList() {
        if dev.IsMouse
            continue
        vidHex := Format("{:04X}", dev.VID)
        pidHex := Format("{:04X}", dev.PID)
        alreadyIn := false
        for dk, dv in Config["devices"] {
            if (dv["vid"] = vidHex && dv["pid"] = pidHex) {
                alreadyIn := true
                break
            }
        }
        if !alreadyIn {
            nk := "detected_" vidHex "_" pidHex
            devKeys.Push(nk)
            devLabels.Push("[detected]  VID " vidHex " / PID " pidHex)
        }
    }

    ; Build app list
    appKeys := [], appLabels := []
    for ak, av in Config["apps"] {
        appKeys.Push(ak)
        appLabels.Push(av["label"])
    }
    appLabels.Push("+ Add new app...")

    ; Resolve initial selections
    selDevIdx := 1
    if g_EditDevice = ""
        g_EditDevice := Config["active_device"]
    for i, dk in devKeys {
        if dk = g_EditDevice {
            selDevIdx := i
            break
        }
    }

    selAppIdx := 1
    if g_EditApp != "" {
        for i, ak in appKeys {
            if ak = g_EditApp {
                selAppIdx := i
                break
            }
        }
    }
    currentApp := (selAppIdx <= appKeys.Length) ? appKeys[selAppIdx] : ""
    profile := (currentApp != "" && Config["apps"].Has(currentApp)) ? Config["apps"][currentApp] : ""

    ; Preset list
    presets := BuildPresets()
    presetKeys := [""], presetLabels := ["--- Load a preset ---"]
    for pk, pv in presets {
        presetKeys.Push(pk)
        presetLabels.Push(pv["label"])
    }

    ; Build GUI
    W := 700
    g := Gui("+Resize", "MacroPad - Edit Mapping")
    g.SetFont("s9", "Segoe UI")
    g.OnEvent("Close", (*) => g.Destroy())

    g.Add("Text",        "x14 y15 w60",        "Device:")
    devDD := g.Add("DropDownList", "x80 y12 w370 h200", devLabels)
    devDD.Value := selDevIdx
    g.Add("Button",      "x458 y11 w100 h24",   "+ Add device").OnEvent("Click", (*) => ShowAddDeviceDialog(g))
    g.Add("Button",      "x563 y11 w120 h24",   "Set as active").OnEvent("Click",  SetActiveDevice.Bind(g, devDD, devKeys))

    g.Add("Text",        "x14 y46 w60",         "App:")
    appDD := g.Add("DropDownList", "x80 y43 w370 h200", appLabels)
    appDD.Value := selAppIdx
    g.Add("Button",      "x458 y42 w100 h24",   "Delete app").OnEvent("Click", DeleteApp.Bind(g, appDD, appKeys))

    g.Add("Text",        "x14 y77 w60",         "Preset:")
    preDD := g.Add("DropDownList", "x80 y74 w370 h200", presetLabels)
    preDD.Value := 1
    g.Add("Button",      "x458 y73 w225 h24",   "Apply preset to current app").OnEvent("Click", ApplyPreset.Bind(g, preDD, presetKeys, currentApp))

    ; Separator
    g.Add("Text", "x14 y103 w676 h1 0x10")

    if profile = "" {
        if currentApp = "" {
            g.Add("Text", "x14 y115 w676 cGray", "No app profiles found. Use the app dropdown to add one.")
        } else {
            g.Add("Text", "x14 y115 w676 cGray", "Select an app above to edit its mapping.")
        }
        g.Add("Button", "x14 y540 w130", "Save && Reload").OnEvent("Click", SaveChanges.Bind(g))
        g.Add("Button", "x154 y540 w80", "Cancel").OnEvent("Click", (*) => g.Destroy())
        g.Show("w" W " h580")
        appDD.OnEvent("Change", OnAppChange)
        devDD.OnEvent("Change", OnDevChange)
        return
    }

    ; Left encoder
    g.Add("GroupBox",    "x14 y110 w320 h80",   "Left Encoder")
    for i, dir in ["ccw", "press", "cw"] {
        entry := profile["left_encoder"][dir]
        lbl := (dir = "ccw") ? "< CCW" : (dir = "press") ? "Press" : "CW >"
        btn := g.Add("Button", "x" (19 + (i-1)*104) " y128 w100 h54", lbl "`n" GetDisplayName(entry))
        btn.OnEvent("Click", OpenCellEditor.Bind(g, currentApp, "left_encoder", dir))
    }

    ; Right encoder
    g.Add("GroupBox",    "x344 y110 w346 h80",  "Right Encoder  (! not device-specific)")
    for i, dir in ["ccw", "press", "cw"] {
        entry := profile["right_encoder"][dir]
        lbl := (dir = "ccw") ? "< CCW" : (dir = "press") ? "Press" : "CW >"
        btn := g.Add("Button", "x" (349 + (i-1)*112) " y128 w108 h54", lbl "`n" GetDisplayName(entry))
        btn.OnEvent("Click", OpenCellEditor.Bind(g, currentApp, "right_encoder", dir))
    }

    ; 4x4 grid
    g.Add("Text",        "x14 y198 cGray",      "4x4 Matrix -- click any key to remap it")
    cellW := 104, cellH := 58, gap := 5, yGrid := 216
    for idx, code in MatrixOrder {
        row := (idx - 1) // 4
        col := Mod(idx - 1, 4)
        x := 14 + col * (cellW + gap)
        y := yGrid + row * (cellH + gap)
        if profile["keys"].Has(code) {
            entry := profile["keys"][code]
            btn := g.Add("Button", "x" x " y" y " w" cellW " h" cellH, entry["label"] "`n" GetDisplayName(entry))
            btn.OnEvent("Click", OpenCellEditor.Bind(g, currentApp, "keys", code))
        }
    }

    ; Process name
    yProc := yGrid + 4 * (cellH + gap) + 8
    g.Add("Text",        "x14 y" yProc " w80",  "Process:")
    procEdit := g.Add("Edit", "x100 y" (yProc - 3) " w280", profile["process"])
    g.Add("Text",        "x390 y" yProc " w300 cGray", "verify in Task Manager > Details")

    ; Save/cancel
    ySave := yProc + 34
    g.Add("Button",      "x14 y" ySave " w130",  "Save && Reload").OnEvent("Click", SaveChangesWithProc.Bind(g, currentApp, procEdit))
    g.Add("Button",      "x154 y" ySave " w80",  "Cancel").OnEvent("Click", (*) => g.Destroy())
    g.Add("Text",        "x244 y" (ySave+5) " w450 cGray", "Writes config.json and reloads immediately.")

    g.Show("w" W " h" (ySave + 52))
    appDD.OnEvent("Change", OnAppChange)
    devDD.OnEvent("Change", OnDevChange)

    OnAppChange(*) {
        global g_EditApp
        idx := appDD.Value
        if idx > appKeys.Length {
            ; "+ Add new app..." selected
            g_EditApp := ""
            g.Destroy()
            ShowAddAppDialog2()
            return
        }
        if idx >= 1 && idx <= appKeys.Length
            g_EditApp := appKeys[idx]
        g.Destroy()
        ShowRemapGui()
    }

    OnDevChange(*) {
        global g_EditDevice
        idx := devDD.Value
        if idx >= 1 && idx <= devKeys.Length
            g_EditDevice := devKeys[idx]
        g.Destroy()
        ShowRemapGui()
    }
}

ApplyPreset(g, preDD, presetKeys, currentApp, *) {
    global Config
    idx := preDD.Value
    if idx < 2 || currentApp = ""
        return
    presets := BuildPresets()
    pk := presetKeys[idx]
    if !presets.Has(pk)
        return
    pr := presets[pk]
    if MsgBox("Apply preset '" pr["label"] "' to '" currentApp "'?`nReplaces all key/encoder mappings and actions.",
        "Apply preset", "YesNo Icon?") != "Yes"
        return
    Config["apps"][currentApp]["keys"]           := pr["keys"]
    Config["apps"][currentApp]["left_encoder"]   := pr["left_encoder"]
    Config["apps"][currentApp]["right_encoder"]  := pr["right_encoder"]
    Config["apps"][currentApp]["actions"]        := pr["actions"]
    g.Destroy()
    ShowRemapGui()
}

SetActiveDevice(g, devDD, devKeys, *) {
    global Config, g_EditDevice
    idx := devDD.Value
    if idx < 1 || idx > devKeys.Length
        return
    dk := devKeys[idx]
    if !Config["devices"].Has(dk) {
        parts := StrSplit(dk, "_")
        vid := parts[2], pid := parts[3]
        Config["devices"][dk] := Map("label","Device_" vid "_" pid,"vid",vid,"pid",pid)
    }
    Config["active_device"] := dk
    g_EditDevice := dk
    MsgBox("Active device set to " Config["devices"][dk]["label"] ".`nSave and reload to apply.", "Device changed", "Iconi")
}

ShowAddDeviceDialog(parentGui, *) {
    d := Gui("+Owner" parentGui.Hwnd, "Add device")
    d.SetFont("s9", "Segoe UI")
    d.OnEvent("Close", (*) => d.Destroy())
    d.Add("Text",, "Label (e.g. Stream Deck, Numpad):")
    labelEd := d.Add("Edit", "w300")
    d.Add("Text", "y+8", "VID (4 hex digits, no 0x prefix):")
    vidEd := d.Add("Edit", "w300")
    d.Add("Text", "y+8", "PID (4 hex digits, no 0x prefix):")
    pidEd := d.Add("Edit", "w300")
    d.Add("Text", "y+8 cGray", "Find these in Device Manager or the Diagnostic.ahk tool.")
    d.Add("Button", "default w80 y+10", "Add").OnEvent("Click", DoAdd)
    d.Add("Button", "x+8 w80", "Cancel").OnEvent("Click", (*) => d.Destroy())
    d.Show()

    DoAdd(*) {
        global Config, g_EditDevice
        lbl := Trim(labelEd.Value)
        vid := Trim(vidEd.Value)
        pid := Trim(pidEd.Value)
        if lbl = "" || StrLen(vid) != 4 || StrLen(pid) != 4 {
            MsgBox("Enter a label and exactly 4 hex digits each for VID and PID.", "Validation", "Iconx")
            return
        }
        dk := RegExReplace(StrLower(lbl), "[^a-z0-9_]", "_")
        Config["devices"][dk] := Map("label",lbl,"vid",StrUpper(vid),"pid",StrUpper(pid))
        g_EditDevice := dk
        d.Destroy()
        parentGui.Destroy()
        ShowRemapGui()
    }
}

ShowAddAppDialog2(*) {
    ShowAddAppDialog("")
}

ShowAddAppDialog(parentGui, *) {
    presets := BuildPresets()
    presetKeys := [], presetLabels := []
    for pk, pv in presets {
        presetKeys.Push(pk)
        presetLabels.Push(pv["label"])
    }

    d := Gui("+Resize", "Add app profile")
    d.SetFont("s9", "Segoe UI")
    d.OnEvent("Close", (*) => d.Destroy())
    d.Add("Text",, "App label (e.g. Capture One, DaVinci Resolve):")
    labelEd := d.Add("Edit", "w360")
    d.Add("Text", "y+8", "Process name (from Task Manager > Details tab, e.g. lightroom.exe):")
    procEd := d.Add("Edit", "w360")
    d.Add("Text", "y+8", "Start from preset:")
    preDD := d.Add("DropDownList", "w360 h200", presetLabels)
    preDD.Value := presetKeys.Length  ; default to blank
    d.Add("Button", "default w80 y+12", "Add").OnEvent("Click", DoAdd)
    d.Add("Button", "x+8 w80", "Cancel").OnEvent("Click", (*) => d.Destroy())
    d.Show()

    DoAdd(*) {
        global Config, g_EditApp
        lbl  := Trim(labelEd.Value)
        proc := Trim(procEd.Value)
        if lbl = "" || proc = "" {
            MsgBox("Enter both a label and a process name.", "Validation", "Iconx")
            return
        }
        ak := RegExReplace(StrLower(lbl), "[^a-z0-9_]", "_")
        pr := BuildPresets()[presetKeys[preDD.Value]]
        Config["apps"][ak] := Map("label",lbl,"process",proc,
            "keys",pr["keys"],"left_encoder",pr["left_encoder"],
            "right_encoder",pr["right_encoder"],"actions",pr["actions"])
        g_EditApp := ak
        d.Destroy()
        ShowRemapGui()
    }
}

DeleteApp(g, appDD, appKeys, *) {
    global Config, g_EditApp
    idx := appDD.Value
    if idx < 1 || idx > appKeys.Length
        return
    ak := appKeys[idx]
    if MsgBox("Delete '" Config["apps"][ak]["label"] "'? This cannot be undone.",
        "Delete app", "YesNo IconX") != "Yes"
        return
    Config["apps"].Delete(ak)
    g_EditApp := ""
    g.Destroy()
    ShowRemapGui()
}

OpenCellEditor(parentGui, appKey, section, key, *) {
    global Config
    profile := Config["apps"][appKey]
    entry   := profile[section][key]
    currentAction := entry["action"]

    actionNames := ["(none)"]
    for name in profile["actions"]
        actionNames.Push(name)

    selIdx := 1
    for i, n in actionNames
        if n = currentAction {
            selIdx := i
            break
        }

    dispName := (section = "keys") ? "Key [" entry["label"] "]"
        : (section = "left_encoder") ? "Left encoder [" key "]"
        : "Right encoder [" key "]  (not device-specific)"

    currentDirect := entry.Has("keys") ? entry["keys"] : ""

    ed := Gui("+Owner" parentGui.Hwnd, "Remap - " Config["apps"][appKey]["label"])
    ed.SetFont("s9", "Segoe UI")
    ed.OnEvent("Close", (*) => ed.Destroy())
    ed.Add("Text", "w520 cGray", Config["apps"][appKey]["label"] " > " dispName)

    ed.Add("Text", "w520 y+10", "Named action (for apps with predefined shortcuts):")
    dd := ed.Add("DropDownList", "w520 h220 r14 y+4", actionNames)
    dd.Value := (currentDirect != "") ? 1 : selIdx
    infoLine := ed.Add("Text", "w520 h28 y+6 cGray", GetActionInfo(actionNames[dd.Value], appKey))
    dd.OnEvent("Change", OnDdChange)

    ed.Add("Text", "w520 y+10", "Custom binding (overrides named action if filled):")
    captureBtn  := ed.Add("Button", "w130 h26 y+4", "Capture key...")
    customEdit  := ed.Add("Edit", "x+8 w378 h26", currentDirect)
    friendlyTxt := ed.Add("Text", "w520 y+4 cGray",
        currentDirect != "" ? "= " AHKToDisplay(currentDirect)
                            : "Click Capture and press a key  —  or type AHK format manually: ^z  +{F5}  {Left}")
    captureBtn.OnEvent("Click", (*) => StartCapture(captureBtn, customEdit, friendlyTxt))
    customEdit.OnEvent("Change", OnCustomChange)

    OnCustomChange(*) {
        v := Trim(customEdit.Value)
        friendlyTxt.Value := v != "" ? "= " AHKToDisplay(v)
                                     : "Click Capture and press a key  —  or type AHK format manually: ^z  +{F5}  {Left}"
    }

    ed.Add("Button", "default w80 y+10", "OK").OnEvent("Click", OkClick)
    ed.Add("Button", "x+8 w80", "Cancel").OnEvent("Click", (*) => ed.Destroy())
    ed.Show()

    OnDdChange(*) {
        infoLine.Value := GetActionInfo(actionNames[dd.Value], appKey)
    }

    OkClick(*) {
        custom := Trim(customEdit.Value)
        if custom != "" {
            ; Direct binding — wipe any named action and store the raw key string
            Config["apps"][appKey][section][key]["action"] := ""
            Config["apps"][appKey][section][key]["keys"]   := custom
        } else {
            ; Named action — clear direct binding
            selected := actionNames[dd.Value] = "(none)" ? "" : actionNames[dd.Value]
            Config["apps"][appKey][section][key]["action"] := selected
            if Config["apps"][appKey][section][key].Has("keys")
                Config["apps"][appKey][section][key].Delete("keys")
        }
        ed.Destroy()
        parentGui.Destroy()
        ShowRemapGui()
    }
}

GetShortName(actionName) {
    global ShortNames
    if actionName = ""
        return "(none)"
    return ShortNames.Has(actionName) ? ShortNames[actionName] : SubStr(actionName, 1, 8)
}

; Use this for grid buttons - shows raw binding string if set, otherwise the action short name.
GetDisplayName(entry) {
    global ShortNames
    if entry.Has("keys") && entry["keys"] != ""
        return entry["keys"]
    actionName := entry["action"]
    if actionName = ""
        return "(none)"
    return ShortNames.Has(actionName) ? ShortNames[actionName] : SubStr(actionName, 1, 8)
}

; Convert an AHK SendInput string to a human-readable label.
; "^+{F5}" -> "Ctrl+Shift+F5",  "^z" -> "Ctrl+Z",  "{Left}" -> "Left"
AHKToDisplay(ahkStr) {
    modMap := Map("^","Ctrl+", "+","Shift+", "!","Alt+", "#","Win+")
    display := ""
    i := 1
    len := StrLen(ahkStr)
    while i <= len {
        ch := SubStr(ahkStr, i, 1)
        if modMap.Has(ch) {
            display .= modMap[ch]
            i++
        } else if ch = "{" {
            closePos := InStr(ahkStr, "}", false, i + 1)
            if closePos > 0 {
                display .= SubStr(ahkStr, i + 1, closePos - i - 1)
                i := closePos + 1
            } else {
                display .= ch
                i++
            }
        } else {
            display .= StrUpper(ch)
            i++
        }
    }
    return display
}

; Build an AHK SendInput-compatible string from a captured key name + modifier prefix.
BuildAHKString(keyName, mods) {
    ; Single-character keys (letters, digits) don't need braces in SendInput.
    ; Everything else (F1, Space, Tab, Left, NumpadX, ...) does.
    return mods . (StrLen(keyName) = 1 ? keyName : "{" keyName "}")
}

; Game-style key capture: click, press the combo, done.
; Uses InputHook so it captures what the user presses on the regular keyboard
; (Interception only blocks the macro pad, so real-keyboard input reaches this hook fine).
StartCapture(captureBtn, ahkEdit, friendlyTxt, *) {
    capturedKey  := ""
    capturedMods := ""

    CaptureKey(ih, vk, sc) {
        keyName := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
        ; Ignore bare modifier presses — keep waiting for the actual key
        if keyName ~= "i)^(L|R)(Ctrl|Shift|Alt|Win)$"
            return
        ; Snapshot modifier state at the exact moment the key was pressed
        ctrl  := GetKeyState("LCtrl")  || GetKeyState("RCtrl")
        shift := GetKeyState("LShift") || GetKeyState("RShift")
        alt   := GetKeyState("LAlt")   || GetKeyState("RAlt")
        win   := GetKeyState("LWin")   || GetKeyState("RWin")
        capturedMods := (ctrl ? "^" : "") . (shift ? "+" : "") . (alt ? "!" : "") . (win ? "#" : "")
        capturedKey  := keyName
        ih.Stop()
    }

    captureBtn.Text    := "Waiting...  Esc = cancel"
    captureBtn.Enabled := false

    ih := InputHook("L0 I T5")        ; L0 = no char limit, I = ignore AHK hotkeys, T5 = 5s timeout
    ih.KeyOpt("{All}", "S")           ; suppress all keys so they don't reach other apps while capturing
    ih.OnKeyDown := CaptureKey
    ih.Start()
    ih.Wait()

    captureBtn.Text    := "Capture key..."
    captureBtn.Enabled := true

    if capturedKey = "" || capturedKey = "Escape"
        return

    ahkStr := BuildAHKString(capturedKey, capturedMods)
    ahkEdit.Value    := ahkStr
    friendlyTxt.Value := "= " AHKToDisplay(ahkStr)
}

GetActionInfo(actionName, appKey) {
    global Config
    if actionName = "(none)" || actionName = ""
        return "Key will do nothing."
    profile := Config["apps"][appKey]
    if !profile["actions"].Has(actionName)
        return "Not in this app's action table."
    action := profile["actions"][actionName]
    note := action.Has("note") ? "  |  " action["note"] : ""
    return "Sends: " action["keys"] "   Status: " (action["supported"] ? "OK" : "unsupported") note
}

SaveChangesWithProc(g, appKey, procEdit, *) {
    global Config
    Config["apps"][appKey]["process"] := Trim(procEdit.Value)
    SaveChanges(g)
}

SaveChanges(g, *) {
    global Config, ConfigPath
    jsonStr := ConfigToJSON(Config)
    try {
        JSON.parse(jsonStr)
    } catch as e {
        MsgBox("Generated JSON is invalid - not saved.`n" e.Message, "Save failed", "Iconx")
        return
    }
    try {
        FileDelete(ConfigPath)
        FileAppend(jsonStr, ConfigPath)
    } catch as e {
        MsgBox("Failed to write config.json: " e.Message, "Save failed", "Iconx")
        return
    }
    g.Destroy()
    Reload()
}

; ============================================================================
; CONFIG SERIALISATION
; ============================================================================

ConfigToJSON(cfg) {
    L := []
    L.Push("{")
    L.Push('  "active_device": "' cfg["active_device"] '",')
    L.Push('  "devices": {')
    dp := []
    for dk, dv in cfg["devices"]
        dp.Push('    "' dk '": { "label": "' dv["label"] '", "vid": "' dv["vid"] '", "pid": "' dv["pid"] '" }')
    L.Push(StrJoin(",`n", dp))
    L.Push('  },')
    L.Push('  "settings": {')
    L.Push('    "block_original_input": ' (cfg["settings"]["block_original_input"] ? "true" : "false") ",")
    L.Push('    "app_specific_mode": '    (cfg["settings"]["app_specific_mode"]    ? "true" : "false"))
    L.Push('  },')
    L.Push('  "apps": {')
    appParts := []
    for ak, av in cfg["apps"] {
        pL := []
        pL.Push('    "' ak '": {')
        pL.Push('      "label": "' av["label"] '",')
        pL.Push('      "process": "' av["process"] '",')
        kp := []
        for code, e in av["keys"] {
            if e.Has("keys") && e["keys"] != ""
                kp.Push('        "' code '": { "label": "' e["label"] '", "action": "", "keys": "' e["keys"] '" }')
            else
                kp.Push('        "' code '": { "label": "' e["label"] '", "action": "' e["action"] '" }')
        }
        pL.Push('      "keys": {') , pL.Push(StrJoin(",`n", kp)) , pL.Push('      },')
        le := []
        for dir, e in av["left_encoder"] {
            if e.Has("keys") && e["keys"] != ""
                le.Push('        "' dir '": { "label": "' e["label"] '", "action": "", "keys": "' e["keys"] '" }')
            else
                le.Push('        "' dir '": { "label": "' e["label"] '", "action": "' e["action"] '" }')
        }
        pL.Push('      "left_encoder": {') , pL.Push(StrJoin(",`n", le)) , pL.Push('      },')
        re := []
        for dir, e in av["right_encoder"] {
            if e.Has("keys") && e["keys"] != ""
                re.Push('        "' dir '": { "label": "' e["label"] '", "action": "", "keys": "' e["keys"] '" }')
            else
                re.Push('        "' dir '": { "label": "' e["label"] '", "action": "' e["action"] '" }')
        }
        pL.Push('      "right_encoder": {') , pL.Push(StrJoin(",`n", re)) , pL.Push('      },')
        ap := []
        for name, action in av["actions"] {
            note := action.Has("note") ? ', "note": "' action["note"] '"' : ""
            ap.Push('        "' name '": { "keys": "' action["keys"] '", "supported": ' (action["supported"] ? "true" : "false") note ' }')
        }
        pL.Push('      "actions": {') , pL.Push(StrJoin(",`n", ap)) , pL.Push('      }')
        pL.Push('    }')
        appParts.Push(StrJoin("`n", pL))
    }
    L.Push(StrJoin(",`n", appParts))
    L.Push('  }')
    L.Push('}')
    return StrJoin("`n", L)
}

StrJoin(delim, arr) {
    r := ""
    for i, v in arr
        r .= (i > 1 ? delim : "") . v
    return r
}
