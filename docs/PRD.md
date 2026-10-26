> **Note:** This is the original product requirements doc as drafted before implementation began. Where implementation diverged from what's written here (e.g. the `FitContributor` permission turned out to actually be `Fit`, and `WatchUi.Picker` was abandoned in favor of a custom input screen), see [`CHANGELOG.md`](../CHANGELOG.md) for the reasoning — this file is kept as-is for historical reference rather than edited after the fact.

# PRD: Pace Target — Garmin Connect IQ Watch App

## Context

Runners often set a goal finish time for a distance (e.g. "finish 10K in 50 minutes") but existing Garmin run apps only show *current* pace, not the pace *required* to hit a target finish time. Runners have to do that math themselves, mid-run, while breathing hard. This app removes that mental overhead: set a distance + target time before starting, and the watch continuously tells you (and buzzes you) whether you're on pace — while still recording a normal, Garmin Connect–synced running activity underneath.

**Outcome:** a standalone Garmin watch app that behaves like the native Run activity (records to Garmin Connect) but adds a live "required pace to finish on time" calculation, a vibration alert when running too slow, and a manual way to tighten the goal time mid-run when ahead of schedule.

## Goals (v1 scope)

1. Runner sets: distance (manual entry or preset: 5K/10K/Half/Marathon) and target finish time, before starting.
2. App records a real running activity (GPS track, distance, duration) that syncs to Garmin Connect like the native Garmin Run app.
3. Live screen shows: required pace (to hit target), current pace, elapsed distance/time, and projected finish time/delta.
4. Vibrate alert when current pace is slower than required pace by more than a configurable buffer.
5. Mid-run, runner can manually lower the target finish time (via button press); app recalculates required pace for the new target for the remaining distance.
6. Broad device compatibility across modern Connect IQ watches (Forerunner, Fenix, Venu families).
7. Units follow the watch's system setting (metric/imperial) — no in-app override.

## Non-goals (explicitly out of scope for v1)

- Run history, post-run analytics/stats screens beyond what Garmin Connect already provides natively.
- Route/map selection or route-based distance calculation.
- Social features, training plans, auto-splits coaching, or auto-detected pace suggestions.
- In-app unit toggle (follows system setting only).
- Support for activity types other than outdoor running.

## User Flow

1. **Launch app** → main menu: "Start Run".
2. **Setup screen**:
   - Pick distance: preset list (5K, 10K, Half Marathon, Marathon, Custom) → Custom opens numeric picker for distance.
   - Enter target finish time via numeric picker (HH:MM:SS).
   - App shows initial required pace (target time ÷ distance) as confirmation before start.
3. **Start** → begins GPS activity recording session (same as native Run activity).
4. **Live run screen** (data fields):
   - Required pace (recalculated continuously off remaining distance/time)
   - Current pace (instantaneous or short rolling average)
   - Elapsed distance, elapsed time
   - Projected finish delta (e.g. "+0:45" ahead/behind)
5. **Pace-too-slow alert**: if current pace is slower than required pace by more than the buffer threshold, sustained over a short trend window, vibrate. Re-arm after pace recovers (avoid buzz spam).
6. **Adjust target (manual button)**: runner presses a dedicated button/menu action mid-run → target finish time decreases by a fixed increment (e.g. −1 min, configurable step) → required pace recalculates immediately against remaining distance.
7. **Stop/Save**: standard Garmin stop-and-save flow → activity saved as FIT file → syncs to Garmin Connect on next sync, appearing as a normal running activity.

## Functional Requirements

| # | Requirement |
|---|---|
| FR1 | Setup screen must support preset distances (5K/10K/Half/Marathon) and custom manual distance entry. |
| FR2 | Setup screen must support manual target finish time entry (HH:MM:SS). |
| FR3 | App must launch a real `ActivityRecording` session (Run sport type) that saves a FIT file syncing to Garmin Connect. |
| FR4 | Required pace = (target time − elapsed time) ÷ (target distance − elapsed distance), recalculated at each GPS/timer tick. |
| FR5 | Current pace displayed as instantaneous or short-window rolling average (to reduce GPS jitter noise) — exact smoothing window is an open tuning parameter, default ~10-30s rolling average. |
| FR6 | Vibrate alert fires when current pace is slower than required pace by more than a buffer (default e.g. 10 sec/km, user-configurable in settings), sustained over a short trend window to avoid noise-triggered buzzing. Alert re-arms only after pace recovers below the buffer. |
| FR7 | Runner can, via a single button press/menu action during the run, decrease the target finish time by a fixed step; required pace recalculates instantly against remaining distance and time. |
| FR8 | Handle GPS-not-yet-acquired state gracefully (Activity.Info fields may be null before fix) — show "Acquiring GPS" state and don't divide-by-zero on pace math. |
| FR9 | On stop, use standard save/discard flow; saved activity must appear in Garmin Connect as a normal run. |
| FR10 | Units (km vs mi, pace format) follow the watch's system unit setting; no in-app toggle. |

## Technical Feasibility (validated against Garmin Connect IQ SDK docs)

All core mechanics are confirmed feasible on Connect IQ (Monkey C):

- **Activity recording & Garmin Connect sync**: `Toybox.ActivityRecording.createSession()` creates a real recording session (start/stop/save), producing a FIT file that syncs like a native activity. Requires declaring the `FitContributor` permission in `manifest.xml`, or `createSession()` throws a runtime permission error.
- **Live GPS/pace data**: `Toybox.Activity.getActivityInfo()` exposes `currentSpeed`, `elapsedDistance`, `currentLocation`. These fields can be `null` before a GPS fix — must null-check. `currentLocation` also requires the Positioning permission.
- **Vibration alerts**: `Toybox.Attention.vibrate()` supported since API 1.0.0, callable during an active recording session. **Gotcha**: Forerunner devices don't support custom vibration duty-cycle patterns — they vibrate at a fixed pattern regardless of what's requested, so don't design UX around distinguishing alert types by vibration pattern.
- **App type**: must be built as a **Watch App** (device app), not a Widget (can't record/use sensors) or Data Field (can only contribute fields to an already-running native activity, doesn't own the session).
- **Manual numeric input**: `WatchUi.Picker` (with `PickerFactory`) is the forward-compatible input control for distance/time entry. `NumberPicker` also exists but is flagged legacy/deprecated post-System-3 — use `Picker`.
- **Device/API level**: target API level ~3.2–4.0 (System 4) covers a broad modern device set (Fenix 5 Plus/6+, Forerunner 245/745/945+, Venu, etc.) while keeping all required APIs (ActivityRecording, Attention, Activity.Info existed since API 1.0.0 — the limiting factor is UI class availability, not core functionality). Real fragmentation risk is screen shape/size and button-vs-touch input, not missing APIs.

## Alert Tuning Parameters (configurable in-app settings)

- Pace buffer threshold (default: e.g. 10 sec/km or /mi slower than required before alerting)
- Trend window for sustained slow-pace detection (default: ~15-30s)
- Manual target-time decrement step (default: 1 minute per button press)

## Open Questions / Decisions Needed Before Build

1. Exact default values for buffer threshold, trend window, and time-decrement step — can be tuned during build/testing, defaults above are starting points.
2. Should the "decrease target time" action also support increasing it back (undo) if the runner presses by mistake or falls behind after tightening the goal?
3. Which specific physical button (or menu path) triggers the target-time adjustment on devices with different button layouts (5-button vs touch-only)?
4. Should there be a secondary alert (e.g. tone, not just vibrate) for devices/users who want dual feedback, or is vibrate-only sufficient for v1?

## Verification Plan

- Build and sideload the app via Connect IQ SDK simulator (`monkeydo`) for at least one representative device per family (e.g. Fenix 7, Forerunner 255, Venu 3) to catch screen-shape/button UI issues.
- Simulate a run in the CIQ simulator with synthetic GPS track data to verify: required-pace math, alert firing/re-arming behavior, target-time adjustment recalculation, and GPS-not-acquired edge case (no crash/divide-by-zero).
- Sideload to a physical Garmin watch, run a real outdoor test, confirm the activity appears correctly in Garmin Connect after sync (correct sport type, distance, GPS track, duration).
- Confirm manifest permissions (`FitContributor`, Positioning) are correctly declared — test that omitting them reproduces the documented permission error, then confirm it's resolved.
