# MacroPad AHI — M1: Diagnostic (AutoHotkey v2 + AutoHotInterception)

This replaces the earlier C#/Raw-Input diagnostic with an AHK v2 script built
on **AutoHotInterception (AHI)**, per your updated direction. Same goal as
before — figure out exactly which physical control produces which event,
before writing a single Lightroom mapping — but now on the architecture
you'll actually keep: AHI's device-specific subscribe/block, which uses the
**Interception** kernel driver (an established, widely-used open-source
driver, not something custom-built for this project).

## One-time setup

1. **Install the Interception driver** — from an elevated (Administrator)
   command prompt, run the driver's `install-interception.exe /install`,
   then **reboot**. This is the actual kernel-level piece that makes
   per-device blocking possible; AHI is a thin AHK wrapper around it.
2. **Assemble the `Lib\` folder — from THREE different places, not one zip:**
   - Download the AHI release zip: `https://github.com/evilC/AutoHotInterception/releases`.
     Extract the **`AHK v2`** folder — that's your working folder. It has a
     `Lib\` with `AutoHotInterception.ahk`, `CLR.ahk`, `Unblocker.ps1` — but
     **not** the DLLs.
   - Still inside the AHI release zip, find `Common\lib\AutoHotInterception.dll`
     and copy it into your working folder's `Lib\`.
   - Separately, download the **Interception driver's own zip** (the one
     with `install-interception.exe`). Inside it is a `library` folder with
     `x86\` and `x64\` subfolders, each containing `interception.dll`. Copy
     both of those folders into your working folder's `Lib\` too.
   - End state:
     ```
     Lib\AutoHotInterception.ahk
     Lib\AutoHotInterception.dll
     Lib\CLR.ahk
     Lib\Unblocker.ps1
     Lib\x86\interception.dll
     Lib\x64\interception.dll
     ```
3. **Unblock the DLLs** — Windows blocks downloaded DLLs by default and AHI
   will fail silently otherwise. Right-click each DLL → Properties → tick
   "Unblock", or just run `Lib\Unblocker.ps1` as Administrator.
4. Copy `Diagnostic.ahk` (this script) into that same working folder, next to
   `Lib\`.
5. Run `Diagnostic.ahk` **as Administrator** — Interception requires
   elevation.

## What the script does

- Calls `AHI.GetDeviceList()` to enumerate every device Interception can see,
  and highlights any whose VID/PID match `0818/D18A`.
- Subscribes to **only** those matching device ID(s) — `SubscribeKeyboard`
  for keyboard-type matches, `SubscribeMouseButtons`/`SubscribeMouseMoveRelative`
  for mouse-type matches (added as a precaution: rotary encoders sometimes
  present as a relative mouse wheel rather than a keyboard scan code or a
  consumer-control usage — better to check than assume).
- Logs every event to a table: time, type, Interception ID, VID, PID, raw
  scan code / button number, a best-effort name guess, and press/release
  state.
- The "Block original input" checkbox is checked by default, matching your
  spec — while it's on, the matched device's native output does **not**
  reach Windows or any app. Uncheck it to test with input passing through
  normally (subscription still logs either way). Your regular keyboard is
  never subscribed, so it's never blocked, checkbox or not.
- "Rescan devices" re-enumerates and re-subscribes — useful since Interception
  device IDs can shift by one after an unplug/replug (documented AHI/driver
  behavior). Automatic reconnect handling is M3; this manual button just
  makes M1 testing survive a replug.
- Closing the window unsubscribes everything cleanly before exit — no
  leftover blocking, no effect on your keyboard ever, regardless of how the
  script exits.

## New in this version: manual device picker + zero-devices troubleshooting

The script now also lists **every** device Interception reports (not just
VID/PID matches) in a dropdown, with a "Subscribe selected" button — useful
if the auto-match ever finds nothing but you want to see what actually got
detected, or subscribe to something manually.

If the summary ever says **"Total Interception devices seen: 0"**, that's a
different, more fundamental problem than a VID/PID mismatch — it means
Interception isn't reporting *any* device, not even your regular keyboard.
That points to one of:
1. The script isn't running elevated — the window title (and a red banner)
   will say so if not. Right-click → Run as administrator.
2. `install-interception.exe /install` was run but the machine was never
   rebooted afterward (required).
3. The Interception service isn't actually running — check with an elevated
   `sc query interception`; it should say `STATE: RUNNING`.

## The important unknown this diagnostic is actually for

Interception attaches as a filter on Windows' `kbdclass.sys` (keyboards) and
`mouclass.sys` (mice). Your 4×4 matrix — almost certainly a standard
Generic-Desktop/Keyboard HID collection — should attach through `kbdclass`
and be fully visible and blockable here.

**Volume Up/Down/Mute are the open question.** If your keypad implements
those via a Consumer Control HID collection (usage page `0x0C`) that Windows
routes straight through `hidclass.sys` without going through `kbdclass` or
`mouclass`, Interception (and therefore AHI) may **not see it at all** — no
device match, no events, no way to block it through this mechanism. Some
devices instead mirror volume keys as ordinary E0-prefixed keyboard scan
codes on the same boot-keyboard interface, in which case they'll show up
here exactly like any other key. There's no way to know which your unit does
without running this and checking.

If the right encoder's volume events genuinely don't appear anywhere in the
log, that's not a bug in the script — it's the actual answer, and it means
M4 will need a different approach for that one control (most likely: detect
it for logging/UI purposes via Raw Input as before, and rely on the fact
that consumer-control volume events don't need "translation to a shortcut"
suppression the same way key events do, or use a small hybrid design). We'll
cross that bridge with real data instead of guessing now.

## What to do

1. Launch the script (as admin). Confirm the summary text at the top shows
   at least one `Matched` device for VID `0x0818` / PID `0xD18A`, and note
   how many IDs it found (1 vs 2 tells us a lot about the device's topology).
2. With the log running, one control at a time:
   - Press all 16 matrix keys (`7 8 9 - / 4 5 6 + / 1 2 3 / / 0 * . Enter`)
   - Left encoder: clockwise, then counter-clockwise, then press
   - Right encoder: clockwise, then counter-clockwise, then press
3. Copy the log rows (select all in the list, or just note them) and send
   them back — specifically, for each of the 22 controls: did anything log
   at all, and if so, which ID/Type/Code fired for it.

If a control produces **nothing**, say so explicitly — that's exactly the
kind of result that decides M2's design, not a failure to fix.

## M2 — Lightroom Desktop remapper (confirmed hardware, real mappings)

Files: `lightroom/Lightroom.ahk`, `lightroom/config.json`, `lightroom/JSON.ahk`.

**Setup:** copy all three files directly into the same "AHK v2" working
folder you already set up for `Diagnostic.ahk` (the one with `Lib\` in it) —
not into a subfolder. `Lightroom.ahk`'s `#Include Lib\AutoHotInterception.ahk`
needs `Lib\` to be its own sibling, same as the diagnostic script.

**What's confirmed vs. not, per the M1 hardware testing:**
- The 16-key matrix and all 3 left-encoder actions: fully confirmed, real
  kernel-level blocking via Interception, working scan codes mapped below.
- Right encoder (Volume Up/Down/Mute): **confirmed NOT visible to
  Interception** — it's a Consumer Control usage-page collection that
  bypasses `kbdclass`/`mouclass` entirely on this hardware. The config has
  placeholders for it but nothing is wired up; it needs a different
  mechanism later (most likely: leave it unblocked and directly correct
  system volume back via the Core Audio API right after each turn, since
  volume is a readable/settable state rather than an interceptable event).

**Device ID is resolved dynamically** via `AHI.GetKeyboardId(VID, PID, 1)`
at startup — never hardcoded, since the numeric Interception ID can shift
after a reconnect. (Automatic re-resolution on unplug/replug is M3's tray
app — for now, if you unplug and replug the keypad, restart this script.)

**Lightroom Desktop shortcuts** (not Classic — genuinely different app,
different bindings) were pulled from Adobe's own reference page and cross-
checked against your requested mapping:

| Key | Action | Shortcut | Status |
|---|---|---|---|
| 7 | Previous photo | Left arrow | confirmed |
| 8 | Next photo | Right arrow | confirmed |
| 9 | Grid view | G | confirmed |
| - | Reject | X | confirmed |
| 4 | Unflag | U | confirmed |
| 5 | Pick | Z | confirmed |
| 6 | Detail view | D | confirmed |
| + | Shift+F6 (cycle panel groups back) | Shift+F6 | confirmed |
| 1 | Undo | Ctrl+Z | confirmed |
| 2 | Redo | Shift+Ctrl+Z | confirmed |
| 3 | Crop | C | confirmed |
| / | Remove tool | Shift+T | confirmed by user testing |
| 0 | Auto Tone | Shift+A | confirmed |
| * | White Balance picker | W | confirmed |
| . | Copy edit settings | Ctrl+C | confirmed |
| Enter | Paste edit settings | Ctrl+V | confirmed |
| Left encoder CW | Tab (cycle within panel group) | Tab | confirmed |
| Left encoder CCW | Shift+Tab | Shift+Tab | confirmed |
| Left encoder press | F6 (cycle panel groups) | F6 | confirmed |
| Right encoder CW | Exposure + | Right arrow | confirmed - requires the keyboard-navigation workflow below |
| Right encoder CCW | Exposure - | Left arrow | same |
| Right encoder press | Activate focused control | Space | same |

**Exposure control workflow** (Lightroom Desktop's own accessibility feature,
found via Preferences → Interface → check both "Accessibility mode" and
"Keyboard navigation"): press **F6 three times, then Tab four times** to
land on the Exposure slider specifically (confirmed sequence for the Basic
panel layout), then **right encoder press (Space)** to activate it, then
turn the right encoder to adjust. The left encoder's Tab/Shift+Tab and press
(F6) map directly onto this same navigation system, so the whole sequence
can be driven from the keypad. If Lightroom's panel layout ever changes,
this exact F6×3/Tab×4 count may need re-confirming.

**Right encoder trade-off:** unlike everything else in this project, the
right encoder is **not device-specific**. It's wired via AHK's own
`Volume_Up`/`Volume_Down`/`Volume_Mute` hotkeys rather than Interception
(confirmed permanently invisible to Interception - see M1 findings), and
AHK hotkeys can't distinguish which physical device triggered them. If your
real keyboard ever has physical volume keys, they'll trigger this mapping
too. When Lightroom isn't focused, the real volume action is explicitly
re-sent so normal system volume control keeps working everywhere else.

**Editing mappings:** open `config.json` — it's structured as
`keys` (scan code → action name) and `actions` (action name → actual
keystroke). Change the keystroke in `actions` to remap what a key does
without touching the scan code table; change `keys` if you want a
*different physical key* to trigger an existing action.

**Lightroom-only mode:** on by default (`"mode": "lightroom-only"` in
config, also toggleable from the tray icon). When on, nothing happens
unless `Lightroom.exe` is the foreground process — verify that's the
actual process name for your install (Task Manager → Details tab while
Lightroom Desktop is running) and update `settings.lightroom_process` in
config.json if it differs.

**Run it:** same as Diagnostic.ahk — as Administrator (Interception
requires elevation). A tray icon appears; right-click it for
Lightroom-only toggle, config reload, and exit.

## Milestone recap (updated)

**M1 — confirmed.** Full 22-control mapping known.

**Interception driver — working**, after a long troubleshooting chain
(Memory Integrity wasn't it; a Defender scan-lock wasn't it; the real
problem was retrying installs against an already-loaded driver file from
an earlier successful attempt — "could not write" was Windows correctly
refusing to overwrite something already in use, not a real blocker).

**M2 (this build) — implemented:** configurable Lightroom Desktop
remapper for the matrix + left encoder, JSON-driven, dynamic device ID
resolution, Lightroom-only foreground gating, tray toggle. Real shortcuts
pulled from Adobe's official reference, two actions honestly marked
unsupported rather than guessed.

**What remains:** right-encoder volume handling (separate mechanism,
scoped as its own piece of work) → M3 tray app / auto-reconnect → M4
extended action set (masking, AI settings, export, etc. — same
documented-shortcuts-only rule applies) → config UI, per your original
milestone list.
