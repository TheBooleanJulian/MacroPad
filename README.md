<div align="center">

# MacroPad

**AutoHotkey remapper for a 16-key + dual-encoder USB macro pad, with per-device kernel-level input capture.**

![AutoHotkey](https://img.shields.io/badge/-AutoHotkey-334455?logo=autohotkey&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)
![License](https://img.shields.io/badge/license-AGPLv3%20%2B%20Commercial-00D4C8.svg)

</div>

---

## What it does

MacroPad remaps a 16-key + dual-encoder USB macro pad (VID `0818` / PID `D18A`) using [AutoHotInterception](https://github.com/evilC/AutoHotInterception) for per-device, kernel-level input capture. Because Interception intercepts the pad at the driver level, its native keystrokes never reach other apps — only whatever action this project remaps them to. Mappings are per foreground application, so the same physical key can trigger a different action depending on what program is focused.

## Features

- Per-device, kernel-level capture via AutoHotInterception/Interception — the pad's native input never leaks to other apps
- Config-driven key mapping in `ahk/config.json`, matched by foreground process name
- Shared per-app `actions` table so a key can be rebound without touching the scan-code table
- In-app "Edit mapping" tray menu that edits and writes `config.json` back out
- Dual rotary encoder support alongside the 16 keys
- Diagnostic tooling (`Diagnostic.ahk`, `debug.log`) for tracing raw scan codes during setup
- Archived legacy C# (Raw Input) implementation kept for reference, no longer maintained

## Tech Stack

| Layer | Choice |
|---|---|
| Live app | AutoHotkey (`ahk/`) |
| Input capture | [AutoHotInterception](https://github.com/evilC/AutoHotInterception) over the Interception kernel driver (`vendor/Interception/`) |
| Config | JSON (`ahk/config.json`), read/written via `ahk/JSON.ahk` |
| Legacy/archived | C# Raw Input prototype (`legacy-csharp/`) — not maintained |

## Screenshots

_Screenshots coming soon._

## Setup / Quick Start

1. Install the Interception kernel driver (one-time, requires a reboot):
   ```
   vendor/Interception/command line installer/install-interception.exe /install
   ```
   Reboot after installing.
2. Run the live app as Administrator (Interception requires elevation):
   ```
   ahk/start.bat
   ```
3. Edit `ahk/config.json` directly, or use the in-app tray menu's "Edit mapping" option, to change per-app key/encoder mappings.

See [`ahk/README.md`](ahk/README.md) for the full config format and per-app mapping reference.

## Project Layout

- **[`ahk/`](ahk/)** — the live app (`MacroPad.ahk`, `Diagnostic.ahk`, `JSON.ahk`, `config.json`, `start.bat`)
- **[`vendor/Interception/`](vendor/Interception/)** — the Interception kernel driver (installer, libraries, licenses) that AutoHotInterception wraps
- **[`legacy-csharp/`](legacy-csharp/)** — an earlier Raw-Input/C# approach, archived and not maintained, kept for reference

## Status / Roadmap

- [x] Kernel-level per-device capture via AutoHotInterception
- [x] Per-app, per-key config with a shared actions table
- [x] In-app tray menu for editing mappings
- [x] Diagnostic tooling for scan-code tracing
- [ ] Packaged installer (currently manual driver install + `start.bat`)
- [ ] Automated tests for the mapping/config logic

## Changelog

- **2026-09-11** — Reorganized the repo: promoted the AutoHotkey app as the live implementation, archived the earlier C# experiment, and tidied the vendored Interception library
- **2026-09-11** — Initial commit of the MacroPad C# app and the AutoHotInterception dependency

## License

This project is dual licensed.

- Community Edition — [GNU Affero General Public License v3 (AGPLv3)](LICENSE). Free to use, modify, and self-host. If you distribute a modified version or run it as a network service, you must make the corresponding source available.
- Commercial License — for organisations that want to embed, modify, or distribute this software without AGPLv3's obligations. See [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md).

---

<div align="center">
<sub>Built by <a href="https://github.com/TheBooleanJulian">@TheBooleanJulian</a></sub>
</div>
