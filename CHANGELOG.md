# Changelog

All notable changes to this project are documented here. Entries are dated and grouped by release; each explains what changed and why, so future contributors can pick up context fast without re-deriving anything from the code alone.

## [Unreleased]

## v1.8.2 — 2026-08-24

- Pace gauge recolored: the too-fast side now draws blue, the too-slow side stays red, matching the existing too-fast/too-slow vibration pattern split.

## v1.8.1 — 2026-08-24

- Added too-fast pace alert (two short buzzes, re-fires every 20s), tracked independently from the too-slow alert so a runner drifting slow→fast doesn't inherit the other direction's arm timer or cooldown.
- Fixed stop-confirm menu leaving the activity recording running underneath it — opening the Save/Discard/Back menu now pauses the session immediately so distance/time freeze while the runner decides.
- Added current pace readout next to Total Time on the live run screen.

## v1.7.0 → v1.7.6 — 2026-08-12

- Fixed no GPS track in the saved activity — `RunView` now enables continuous location events on show and disables them on hide, so the FIT session records a route.
- Fixed stop/confirm flow bugs: back-button un-pausing the run, resume-from-menu ignoring pause state, and `returnToStartScreen()` not unwinding the full view stack.
- Added GPS-activation gate screen between setup and start — waits for a usable GPS fix before recording begins, with an optional skip-wait press for when no fix is available.
- Fixed launcher icon opaque navy background — re-saved as RGBA with transparency.

## v1.6.0 — 2026-08-09

- Added launcher icon (stopwatch + pace-arrow glyph).
- Added repeating too-slow vibrate alert — fires on a configurable cadence while pace stays slow, re-arming only after pace recovers.
- Added mid-run pause/resume (short press) and long-press-to-stop with run summary menu.
- Save/Discard now return to the start screen instead of closing the app outright.

## v1.1.0 → v1.1.1 — 2026-07-28

- Physical-button-only confirm actions: swipe to adjust values, physical select button to confirm. Tap-to-confirm removed to avoid accidental triggers mid-run.
- Pace gauge redesigned as a circumferential arc around the bottom of the round face.
- Added app version display on the distance-menu screen (kept in sync with `manifest.xml`).
- Fixed `onTap` default fallthrough to `onSelect` — both `onTap` and `onSelect` are now explicitly handled so physical-button input is distinct from touchscreen taps.
- Pace bar with required-pace deviation marker and total time on the run screen.

## v1.2.0 → v1.2.3 — 2026-07-29

- Added Start Confirm screen before recording begins, showing target distance/time summary.
- Added green bezel button-marker arc to all entry screens.
- Fixed layout overlap on the start-confirm screen.

## v1.1.0 — 2026-07-28

- Abandoned `WatchUi.Picker` in favor of a custom self-drawn `NumberEntryView` for distance/time entry — Picker's touch layout and hit-testing proved unreliable and undocumented.
- Added chained entry flow: distance (custom) → hours → minutes → seconds → start confirm → run screen.

## v1.0.0 — 2026-07-27

- Initial project scaffold: `manifest.xml`, `monkey.jungle`, resource strings, placeholder launcher icon.
- Core features: distance + target-time entry, live required-pace tracking, too-slow vibrate alert, mid-run goal tightening, activity recording synced to Garmin Connect.
