#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
; MacroPad AHI Diagnostic - MILESTONE 1
; ============================================================================
; Confirms EXACTLY which physical controls on the VID_0818 / PID_D18A keypad
; are visible through AutoHotInterception (AHI), and blocks ONLY that device's
; original input while this window is open. Your normal keyboard is never
; touched - AHI subscribes/blocks per Interception device ID, not globally.
;
; SETUP (do this once, before running):
;   1. Install the Interception driver from an elevated (Administrator)
;      command prompt:
;         install-interception.exe /install
;      then REBOOT. This is the well-established, widely-used driver AHI
;      wraps - not a custom kernel driver.
;   2. Download an AHI release (AHK v2 build) and build a Lib\ folder from
;      it (AutoHotInterception.ahk + .dll + CLR.ahk + x86\/x64\ interception.dll -
;      see README for exactly which zip each file comes from).
;   3. Unblock the DLLs (Lib\Unblocker.ps1, run as admin).
;   4. Copy THIS FILE next to that Lib\ folder.
;   5. Run this script AS ADMINISTRATOR - Interception requires elevation.
;
; IMPORTANT KNOWN UNKNOWN (this is exactly what M1 exists to resolve):
;   Interception attaches as an upper filter on Windows' kbdclass.sys and
;   mouclass.sys. Your 4x4 matrix (HID usage page 0x01/usage 0x06, Keyboard)
;   should attach through kbdclass and be fully visible/blockable here.
;   Volume Up/Down/Mute are commonly implemented via a Consumer Control
;   collection (usage page 0x0C) - devices that go through hidclass.sys but
;   NOT through kbdclass/mouclass are effectively invisible to Interception
;   (and therefore to AHI). Some devices *also* mirror media keys as
;   E0-prefixed scan codes on the keyboard boot interface, in which case they
;   WILL show up here just fine. We don't know which your keypad does until
;   this diagnostic tells us - don't assume either way.
;
; IF THE SUMMARY EVER SAYS "Total Interception devices seen: 0":
;   That means Interception isn't reporting ANY device - not even your
;   normal keyboard. That's not a VID/PID problem, it means the driver
;   itself isn't active for this process. Check, in order:
;     1. Is this script running elevated? (the window title below will
;        say so if not)
;     2. Was install-interception.exe /install actually run (elevated),
;        and did you reboot afterwards?
;     3. Run "sc query interception" in an elevated cmd - it should show
;        STATE: RUNNING.
; ============================================================================

#Include ..\Lib\AutoHotInterception.ahk

TargetVID := 0x0818
TargetPID := 0xD18A

global AHI := AutoHotInterception()
global Matched := Map()        ; Interception ID -> device info, for devices currently subscribed
global AllDevicesCache := Map() ; Interception ID -> device info, from the most recent scan (all of them)
global DdlIds := []             ; parallel array: dropdown list index -> Interception ID

; ---------------------------- GUI ----------------------------

titleSuffix := A_IsAdmin ? "" : "  [NOT RUNNING AS ADMIN - Interception will see 0 devices]"
MainGui := Gui("+Resize", "MacroPad AHI Diagnostic (M1)" titleSuffix)
MainGui.OnEvent("Close", (*) => ExitApp())
MainGui.SetFont("s10", "Segoe UI")

if (!A_IsAdmin) {
    warn := MainGui.Add("Text", "w640 cRed", "WARNING: this script is not elevated. Right-click it and choose 'Run as administrator', or Interception will report 0 devices.")
}

MainGui.Add("Text", "w640", "Target device: VID 0x" Format("{:04X}", TargetVID) "  PID 0x" Format("{:04X}", TargetPID) "  (SIDE-KEYBOARD)")
SummaryText := MainGui.Add("Text", "w640 h80", "Scanning...")

MainGui.Add("Text", "w640", "All Interception devices found (pick one manually if auto-match above found nothing):")
AllDdl := MainGui.Add("DropDownList", "w500", ["(rescan to populate)"])
SubscribeSelectedBtn := MainGui.Add("Button", "x+10 w120", "Subscribe selected")
SubscribeSelectedBtn.OnEvent("Click", (*) => SubscribeSelected())

BlockCheck := MainGui.Add("Checkbox", "w640 xm Checked", "Block original input from matched/selected device(s) while this window is open")
BlockCheck.OnEvent("Click", OnBlockToggle)

RescanBtn := MainGui.Add("Button", "w150", "Rescan devices")
RescanBtn.OnEvent("Click", (*) => ScanAndSubscribe())

ClearBtn := MainGui.Add("Button", "x+10 w150", "Clear log")
ClearBtn.OnEvent("Click", (*) => LV.Delete())

LV := MainGui.Add("ListView", "w640 h340 xm", ["Time", "Type", "ID", "VID", "PID", "Code/Btn", "Name guess", "State"])
LV.ModifyCol(1, 85)
LV.ModifyCol(2, 75)
LV.ModifyCol(3, 35)
LV.ModifyCol(4, 60)
LV.ModifyCol(5, 60)
LV.ModifyCol(6, 90)
LV.ModifyCol(7, 140)
LV.ModifyCol(8, 60)

MainGui.Show()

OnExit(CleanupAndExit)

ScanAndSubscribe()
return

; ---------------------------- Core logic ----------------------------

; (Re)enumerates all Interception devices, unsubscribes any previously
; matched/selected device (safe to call again after a reconnect, when
; Interception IDs can shift), auto-subscribes anything matching VID/PID,
; and repopulates the "all devices" dropdown for manual fallback.
ScanAndSubscribe() {
    global AHI, Matched, AllDevicesCache, DdlIds, TargetVID, TargetPID, BlockCheck, SummaryText, AllDdl

    for id, dev in Matched
        UnsubscribeOne(id, dev)
    Matched := Map()

    allDevices := AHI.GetDeviceList()
    AllDevicesCache := allDevices
    blockInput := BlockCheck.Value

    ; Rebuild the manual-pick dropdown from EVERY device Interception can see,
    ; regardless of VID/PID - this is what tells us whether the "0 matches"
    ; problem is a VID/PID issue or an "Interception sees nothing at all" issue.
    ddlItems := []
    DdlIds := []
    for id, dev in allDevices {
        ddlItems.Push(Format("ID {1}  {2}  VID=0x{3:04X}  PID=0x{4:04X}  Handle={5}",
            id, dev.IsMouse ? "Mouse" : "Keyboard", dev.VID, dev.PID, dev.Handle))
        DdlIds.Push(id)
    }
    if (ddlItems.Length = 0)
        ddlItems.Push("(no devices reported by Interception - see troubleshooting notes at top of script)")
    AllDdl.Delete()
    AllDdl.Add(ddlItems)
    AllDdl.Choose(1)

    matchLines := []
    for id, dev in allDevices {
        if (dev.VID = TargetVID && dev.PID = TargetPID) {
            matchLines.Push(Format("  ID={1}   Type={2}   VID=0x{3:04X}   PID=0x{4:04X}   Handle={5}",
                id, dev.IsMouse ? "Mouse" : "Keyboard", dev.VID, dev.PID, dev.Handle))
            SubscribeOne(id, dev, blockInput)
        }
    }

    if (matchLines.Length = 0) {
        extra := ""
        if (allDevices.Count = 0)
            extra := "`n0 total devices means Interception isn't seeing ANYTHING (not even a normal keyboard) - " .
                "that's an elevation/driver-service problem, not a VID/PID problem. See notes at top of script."
        else
            extra := "`nUse the dropdown above to inspect what WAS found and subscribe manually if needed."
        SummaryText.Text := "No Interception device currently matches VID/PID 0818/D18A.`n" .
            "Total Interception devices seen: " allDevices.Count . extra
    } else {
        SummaryText.Text := "Matched " matchLines.Length " Interception device ID(s), blocking=" (blockInput ? "ON" : "OFF") ":`n" .
            JoinLines(matchLines) . "`n" .
            "If you expected 2 interfaces here (MI_00 and MI_01) but only see 1, the missing one is " .
            "likely not routed through kbdclass/mouclass - see comments at top of script."
    }
}

; Manual override: subscribe to whatever is currently chosen in the "all
; devices" dropdown, regardless of whether it matched VID/PID automatically.
; Useful if auto-match finds nothing but devices clearly ARE listed.
SubscribeSelected() {
    global AllDdl, DdlIds, AllDevicesCache, Matched, BlockCheck, SummaryText

    idx := AllDdl.Value
    if (idx = 0 || DdlIds.Length = 0) {
        SummaryText.Text := "No device selected in the dropdown - rescan first."
        return
    }
    id := DdlIds[idx]
    if (!AllDevicesCache.Has(id)) {
        SummaryText.Text := "Selected device is no longer in the cached list - rescan."
        return
    }
    dev := AllDevicesCache[id]
    SubscribeOne(id, dev, BlockCheck.Value)
    SummaryText.Text := Format("Manually subscribed to ID {1} ({2}, VID=0x{3:04X} PID=0x{4:04X}). Watch the log below.",
        id, dev.IsMouse ? "Mouse" : "Keyboard", dev.VID, dev.PID)
}

SubscribeOne(id, dev, blockInput) {
    global AHI, Matched
    if (dev.IsMouse) {
        AHI.SubscribeMouseButtons(id, blockInput, MouseButtonEvent.Bind(id, dev))
        AHI.SubscribeMouseMoveRelative(id, blockInput, MouseMoveEvent.Bind(id, dev))
    } else {
        AHI.SubscribeKeyboard(id, blockInput, KeyboardEvent.Bind(id, dev))
    }
    Matched[id] := dev
}

KeyboardEvent(id, dev, code, state) {
    LogRow("Keyboard", id, dev, code, GuessKeyName(code), state)
}

MouseButtonEvent(id, dev, btn, state) {
    LogRow("MouseBtn", id, dev, btn, "-", state)
}

MouseMoveEvent(id, dev, x, y) {
    global LV
    LV.Add(, FormatTime(, "HH:mm:ss"), "MouseMove", id,
        Format("0x{:04X}", dev.VID), Format("0x{:04X}", dev.PID),
        "dx=" x " dy=" y, "-", "-")
    LV.Modify(LV.GetCount(), "Vis")
}

LogRow(type, id, dev, codeOrBtn, guess, state) {
    global LV
    LV.Add(, FormatTime(, "HH:mm:ss"), type, id,
        Format("0x{:04X}", dev.VID), Format("0x{:04X}", dev.PID),
        codeOrBtn, guess, state ? "DOWN" : "UP")
    LV.Modify(LV.GetCount(), "Vis")
}

; Best-effort scan-code -> key name guess, tried both as a plain scan code
; and as an "extended" (E0-prefixed) one per AHK's own sc1xx convention.
; This is a HINT for readability only - the raw Code/Btn column is the
; actual data to report back; don't take this guess as confirmed fact.
GuessKeyName(code) {
    try {
        plain := GetKeyName(Format("sc{:x}", code))
        if (plain != "")
            return plain
    }
    try {
        ext := GetKeyName(Format("sc{:x}", code | 0x100))
        if (ext != "")
            return ext " (ext?)"
    }
    return "?"
}

OnBlockToggle(ctrl, *) {
    ScanAndSubscribe()
}

UnsubscribeOne(id, dev) {
    global AHI
    try {
        if (dev.IsMouse) {
            AHI.UnsubscribeMouseButtons(id)
            AHI.UnsubscribeMouseMoveRelative(id)
        } else {
            AHI.UnsubscribeKeyboard(id)
        }
    }
}

JoinLines(arr) {
    out := ""
    for i, v in arr
        out .= (i = 1 ? "" : "`n") v
    return out
}

CleanupAndExit(*) {
    global Matched
    for id, dev in Matched
        UnsubscribeOne(id, dev)
}
