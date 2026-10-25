# MacroPad — TODO

## Verify
- [ ] Run `ahk/start.bat` as admin and confirm the new stay-in-tray behaviour works (the last change to `MacroPad.ahk` was never run; no syntax check was possible)
- [ ] Reboot with the pad plugged in to reset Interception's slots (keyboard IDs 5–10 and mouse IDs 18–20 are used up), then confirm the pad subscribes
- [ ] Test "Rescan device" from the tray after plugging the pad in late
- [ ] Test picking a different pad via Edit mapping → Device → "Set as active" → Save & Reload

## Known issues / ideas
- [ ] The "slots used up" check reads the whole `debug.log` and never resets after a reboot, so a stale ID 9+ can trigger a wrong message. Ignore log entries from before the last boot
- [ ] Rescan can't free Interception slots; only a reboot does. Consider a tray status line showing slots in use
- [ ] Auto-rescan on USB change (WM_DEVICECHANGE) or a timer, so no manual "Rescan device" click is needed
- [ ] `debug.log` grows without bound (~500 KB, 15k lines); rotate or trim on startup

## From README roadmap
- [ ] Packaged installer (currently manual driver install + `start.bat`)
- [ ] Automated tests for the mapping/config logic
- [ ] Add screenshots to README

## Housekeeping
- [ ] Repo only has `master`, no `dev` branch, so the global feature → dev → main workflow isn't set up here yet
- [ ] README changelog doesn't mention the Oct 2026 startup changes
