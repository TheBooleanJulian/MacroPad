> **Archived.** This C#/Raw-Input approach was superseded by the AHK +
> AutoHotInterception app in [`ahk/`](../ahk/) once the Interception driver
> install issue below got sorted out. Kept here for reference only.

# MacroPad — M1 diagnostic + M3/M4 suppression (no kernel driver)

## Status

- **M1 (diagnostic) — done and confirmed.** All 22 controls mapped:
  the 16-key matrix and all 3 left-encoder actions arrive as ordinary
  keyboard-type Raw Input events on one collection (`MI_01`); the right
  encoder's Volume Up/Down/Mute arrive as Consumer Control HID reports on
  `MI_00/Col03`. Full table is in the chat, also reflected in `MappingTable.cs`.
- **Interception driver path — abandoned.** Hit a Windows Memory
  Integrity (HVCI) block on `install-interception.exe /install`
  ("Could not write to \system32\drivers") that wasn't worth fighting
  further for a personal macro pad.
- **M3/M4 (this build) — capture + suppression, no kernel driver.**
  `--suppress` mode actively blocks the matched device's input
  system-wide using a Raw-Input/low-level-hook correlation trick (see
  below), and logs every suppressed event. **Not yet wired to Lightroom**
  — suppressed events are only logged with a friendly label so far;
  actual `SendInput`-based action injection is the next step once
  suppression itself is confirmed reliable on your machine.

## How suppression works (read this before running `--suppress`)

There's no built-in Windows API that both (a) tells you which physical
device an event came from and (b) can block it from reaching other
apps. Raw Input does (a). A global low-level keyboard hook
(`WH_KEYBOARD_LL`) does (b) but has no idea which device fired it.

`SuppressionEngine.cs` bridges the two with a timing correlation: when
Raw Input reports an event from your keypad, it's stashed (VKey,
down/up, timestamp). When the hook sees a matching VKey+state within
~30ms, that's treated as "the keypad" and blocked; anything unmatched
(your real keyboard, anything else) passes straight through.

**Honest limitation:** this is a heuristic, not a hardware-level
guarantee like the Interception driver would have given us. If you
pressed the *exact same key* on your real keyboard and the macro pad
within ~30ms of each other, one event could theoretically be
misattributed. For a dedicated macro pad this isn't a realistic
scenario, but it's a categorically different guarantee than a kernel
filter driver, and worth knowing going in.

**Volume events specifically:** Consumer Control usages 0xE9/0xEA/0xE2
are mapped to the VKs Windows conventionally synthesizes for them
(`VK_VOLUME_UP`/`DOWN`/`MUTE`, 0xAF/0xAE/0xAD) — this hasn't been
separately confirmed on your machine. If it's right, turning the right
encoder logs `SUPPRESSED` and your system volume stops changing while
this is running. If it's wrong, it'll log nothing for the encoder and
volume will keep changing — that's the answer, no separate test needed.

## Build & run (Windows, .NET 8 SDK required)

This project lives in a Google Drive-synced folder, which breaks the
normal `dotnet build` apphost step. Two batch files handle the
workaround for you — just double-click:

- **`run-diagnostic.bat`** — re-confirm the device topology (`--diagnostic`)
- **`run-suppress.bat`** — build and start suppression mode (`--suppress`)

Manually, the equivalent commands are:

```
dotnet build -p:UseAppHost=false
dotnet bin\Debug\net8.0-windows\MacroPad.dll --diagnostic
dotnet bin\Debug\net8.0-windows\MacroPad.dll --suppress
```

Close any previously-running instance before rebuilding — the DLL gets
locked while it's running and the build will fail with a file-in-use
error otherwise.

## What to test with `--suppress`

1. Launch it, confirm it finds the device and installs the hook.
2. **Type normally in Notepad** on your real keyboard the whole time —
   confirm nothing is different. This is the most important check.
3. Press each of the 16 matrix keys and both encoder buttons on the
   keypad — each should log `SUPPRESSED` with its label, and **nothing
   should appear in Notepad** (previously these numpad digits would
   type into whatever's focused).
4. Turn the right encoder — check Windows' volume indicator does **not**
   move, and check whether it logs `SUPPRESSED` or nothing at all.
5. Turn the left encoder and press it — same check for Backspace/Space/NumLock
   no longer doing anything in Notepad.

Send back: did steps 2–3 fully pass, and specifically what happened in
step 4 (volume changed or not, logged or not).

## Milestone recap

**M1 — confirmed.** Full 22-control mapping known (see table above /
`MappingTable.cs`).

**M3/M4 (this build) — implemented:** device-specific capture via Raw
Input + system-wide suppression via a correlated low-level hook, no
kernel driver, no admin/Secure Boot dependency. Logging only — no
Lightroom actions triggered yet.

**What we don't know yet:** whether the volume-VK correlation
assumption holds on your hardware, and whether the ~30ms window is
comfortable in real use (too tight → some legitimate presses might
occasionally pass through unsuppressed; too loose → very slightly more
misattribution risk on the real keyboard, though in practice this
window is standard for this kind of correlation trick).

**What remains:** once suppression is confirmed solid, add the actual
Lightroom `SendInput` action table (M5), then foreground-detection
(M6), full encoder mode-switching (M7), config UI (M8), and tray/reconnect
handling (M9) — per your original milestone list.

