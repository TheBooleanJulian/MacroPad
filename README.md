# MacroPad

AutoHotkey remapper for a 16-key + dual-encoder USB macro pad (VID `0818` /
PID `D18A`), using [AutoHotInterception](https://github.com/evilC/AutoHotInterception)
for per-device, kernel-level input capture — the pad's native keystrokes never
reach other apps, only whatever this remaps them to.

## Layout

- **[`ahk/`](ahk/)** — the live app. Run `ahk/start.bat` as Administrator
  (Interception requires elevation). See [`ahk/README.md`](ahk/README.md)
  for setup, config format, and per-app key mappings.
- **[`vendor/Interception/`](vendor/Interception/)** — the Interception
  kernel driver (installer, libraries, licenses) that AutoHotInterception
  wraps. One-time install: `vendor/Interception/command line installer/install-interception.exe /install`,
  then reboot.
- **[`legacy-csharp/`](legacy-csharp/)** — an earlier Raw-Input/C# approach,
  archived. Not maintained; kept for reference.

## Config

`ahk/config.json` maps scan codes and encoder actions per foreground app
(matched by process name), with a shared per-app `actions` table so you can
rebind a key without touching the scan-code table. Edit it directly, or use
the in-app "Edit mapping" tray menu, which writes it back out.
