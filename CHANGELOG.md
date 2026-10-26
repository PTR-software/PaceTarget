# Changelog

All notable decisions and changes to this project are recorded here, in addition to what git history shows. Entries are dated and grouped; each should explain **why**, not just what, so future work (by a person or an AI session) can pick up context fast without re-deriving it. When you make a decision or a non-trivial change, add an entry here in the same turn — don't defer it.

## 2026-08-24 (v1.8.2) — pace gauge's "too fast" side recolored blue

User ask: the pace gauge's left (too-fast) segment was red, same as the right (too-slow) segment - both ends looked identical at a glance, only distinguishable by position on the arc.
- `RunView.drawPaceGauge()`: split the single full-span `dc.drawArc()` red draw into two - `GAUGE_START_ANGLE` to `greenStart` (too-fast side) now `Gfx.COLOR_BLUE`, `greenEnd` to `GAUGE_END_ANGLE` (too-slow side) stays `Gfx.COLOR_DK_RED`. `greenStart`/`greenEnd` (buffer-zone bounds) computed before the color draws now, since both segments need them.
- Matches the v1.8.0 too-fast/too-slow vibe-pattern split (two short buzzes vs. one long buzz) - now the gauge's colors agree with the alert direction too, not just its position.
- Verified: rebuilt/pushed via `scripts/run-sim.sh`, `BUILD SUCCESSFUL`, auto-drive ran entry→GPS-gate→run with pause/resume, zero crashes. **Color not visually confirmed** (no screen access this session) - only confirmed the arc-splitting logic compiles and runs without crashing, not that blue actually renders on the left side as intended.

## 2026-08-24 (v1.8.0 → v1.8.1) — too-fast alert, finish no longer keeps recording underneath the confirm menu, current pace on screen

Three asks in one session: a new too-fast vibrate alert, a real bug where "finishing" a run didn't actually freeze it, and a missing on-screen stat.

### Added (v1.8.0) — too-fast pace alert (two short buzzes, re-fires every 20s)
`PaceAlert.mc` only ever detected "too slow" (`current - required > buffer`). Added the mirror direction, `isFast` (`current - required < -buffer`), tracked with its own independent arm/re-fire state (`_fastSinceMs`/`_fastLastFireMs`, separate from the slow pair) so a runner drifting slow→fast doesn't inherit the other direction's arm timer or wait out its cooldown.
- Same trend-window arm delay (`Globals.trendWindowSeconds`, 20s) as the slow alert, for consistency - fires once sustained fast, then re-fires every `Globals.fastAlertRepeatSeconds` (new constant, 20s, deliberately separate from `alertRepeatSeconds`=15s so the two cadences can be tuned independently even though they start at the same value).
- Vibe pattern deliberately different from the slow alert's single 1000ms buzz: two 150ms buzzes with a 150ms gap (`Attention.VibeProfile(0, 150)` as the gap), so the runner can tell which direction fired by feel alone, without looking at the watch.
- Gauge/threshold already treated fast/slow symmetrically (`GAUGE_START_ANGLE`/`GAUGE_END_ANGLE` in `RunView.mc` already labels one side "too fast", the other "too slow", both bounded by the same `paceBufferSecPerKm`) - this just makes the vibrate alert agree with what the gauge already implied.

### Fixed (v1.8.0) — stop-confirm menu left the session recording underneath it
Real report: "when I finish the run - all should be paused (now, timer still goes on)". Root cause: `promptStopConfirm()` (`SaveConfirmMenu.mc`) only ever built and pushed the Save/Discard/Back menu - it never touched the `ActivityRecording` session. Only the `:save`/`:discard` branches called `session.stop()`. So opening the menu (long-press, or back button) left distance/time accruing in the FIT session for however long the runner spent deciding, even though the screen underneath was hidden (view `onHide()` stops RunView's own 1Hz display timer and disables the position callback, but that's cosmetic - it doesn't stop the session itself).
- `RunView.mc`: added `pauseForConfirm()` - mirrors the existing pause mechanism (`session.stop()`), sets `_paused = true`. No-ops (and leaves a `_autoPausedForMenu` flag false) if the run was already paused by the user, so a genuinely user-paused run doesn't get miscredited to the menu.
- `RunView.mc`: added `resumeFromConfirmBack()` - undoes `pauseForConfirm()` only if `_autoPausedForMenu` is true, i.e. only if this exact call is what paused it. Called from the `:back` branch before `Ui.popView(...)`; `RunView.onShow()`'s existing `!_session.isRecording() && !_paused` guard (see 2026-08-12 entry below) makes the subsequent onShow()-refire on menu-pop a safe no-op either way.
- `SaveConfirmMenu.mc`: `promptStopConfirm()` now calls `runView.pauseForConfirm()` as its first line, before building the summary text, so the summary itself reflects the frozen numbers.
- Verified: rebuilt/pushed via `scripts/run-sim.sh`, `BUILD SUCCESSFUL`, auto-drive ran full entry→GPS-gate→run→pause/resume flow with zero crashes. **Not independently confirmed on the actual repro** (finish → wait a few seconds on the confirm menu → Back → check total time didn't jump) - the auto-drive harness doesn't dwell on that menu, needs the user's hands.

### Added (v1.8.1) — current pace next to Total Time on the run screen
Real report: "I am missing the information on what is my current pace." The live run screen (`RunView.onUpdate`) drew Total Time, Required Pace, and Distance, but never the runner's actual current pace anywhere - only the gauge showed deviation, with no numeric value.
- `RunView.mc`: added `drawLabeledValuePair()`, a two-column variant of the existing `drawLabeledValue()` (same "returns the drawn value's bottom Y" contract, so callers can still chain without guessing at overlap) - draws two label/value pairs side by side at the same `yTop` instead of stacked.
- Total Time row now uses it: Total Time on the left, Current Pace (`PaceMath.formatMmSs(_currentPace)`, already null-safe -> "--:--" pre-fix) on the right, at `w*0.27`/`w*0.73`. Dropped from `FONT_MEDIUM` to `FONT_SMALL` so both columns fit without crowding on a ~450px round face.
- New string `LabelCurrentPace` ("Cur Pace" - same abbreviation style as the existing "Req Pace"/"Dist").
- This row is only drawn in the non-paused branch (an unrelated PAUSED-label restructure, made outside this session before this change, already suppressed Total Time entirely while paused - Current Pace follows the same already-established rule rather than introducing a new one).
- Verified: rebuilt/pushed, `BUILD SUCCESSFUL`, auto-drive exercised entry→run→pause/resume with zero crashes. **Layout not visually confirmed** (no screen access this session) - flagged per the column-position math (`w*0.27`/`w*0.73`) not having been eyeballed against actual rendered text width; if the two columns look cramped or overlap, that's the first thing to check.

## 2026-08-12 (v1.7.1 → v1.7.6) — no GPS route recorded, then a chain of pause/stop-menu bugs

Four separate user reports in one session, each fixed and redeployed individually per the version-bump-every-redeploy rule.

### Fixed (v1.7.1) — no GPS track in the saved activity
Real report: after a run, Garmin Connect showed no route/map for the activity. Root cause: `GpsAcquireView.proceed()` (added same day in v1.7.0) called `Pos.enableLocationEvents(Pos.LOCATION_DISABLE, ...)` right before handing off to `StartConfirmView` → `RunView`. `RunView` never re-enabled location events itself - it only ever called `Record.createSession()` + `session.start()`. Net effect: the FIT session recorded fine (distance/pace still worked off `Activity.Info`, masking the bug during the run), but with GPS position events off the whole time, so no track ever landed in the file.
- `GpsAcquireView.proceed()`: removed the disable call. Ownership of the GPS stream now hands off live to `RunView` instead of being torn down and expected to restart cold.
- `RunView.mc`: added `using Toybox.Position`; `onShow()` now calls `Pos.enableLocationEvents(Pos.LOCATION_CONTINUOUS, method(:onPositionInfo))` (handler is a no-op - `onTimerTick()` already reads the same stream via `Activity.getActivityInfo()`); `onHide()` now disables location events symmetrically with the existing timer stop/start.
- Verified: rebuilt/pushed, auto-drive harness ran full entry→GPS-gate→run flow four times across this session's builds with zero crashes.

### Investigated, added, then reverted (v1.7.2 → v1.7.3) — stop-during-pause via top-button hold doesn't work on real hardware
User report: holding the top (Action) button to reach the stop-confirm menu instead toggles the watch's own Do Not Disturb / Controls - a system-reserved gesture on that physical button that the app never gets a chance to intercept (`onKeyPressed`/`onKeyReleased`'s hold-duration logic in `RunDelegate.mc` never fires). Same class of issue as the `onSelect`/`onTap` fusion found 2026-07-28 round 3: don't trust intuition about who owns a physical gesture, verify.
- v1.7.2: repurposed tap on the paused run screen (page 0) to open the stop-confirm menu, using the same "tap is safe once the screen is reached deliberately" reasoning already applied to the target page (v1.5.0). User rejected this on sight ("I don't like this") before further testing.
- v1.7.3: reverted the tap-while-paused change entirely, back to swallowing tap unconditionally on page 0. Real alternative left in place and unchanged: `RunDelegate.onBack()` already calls `promptStopConfirm()` unconditionally, no hold required, regardless of pause state - untested on real hardware as of this entry, but doesn't depend on the same reserved-button-hold gesture, so lower risk.

### Fixed (v1.7.4 → v1.7.5) — Resume from the stop-confirm menu ignored/corrupted pause state
User report: back button → stop-confirm menu → Resume left the screen showing "PAUSED" while pace/time kept advancing underneath.
- v1.7.4: root cause first found in `SaveConfirmMenu.mc`'s `:resume` item, which called `session.start()` directly without ever touching `RunView._paused` - added `RunView.resumeFromMenu()` to fix it (force-clear `_paused`, start session if needed).
- Follow-up ask: don't force-resume at all - if the run was paused before opening the menu, leaving the menu should leave it paused, not always running. Realized the correct fix is that this branch shouldn't touch session/pause state in either direction - opening the menu never changed it, so returning shouldn't either. Also renamed the menu item **Resume → Back** (`LabelResume` → `LabelBack` in `strings.xml`) since "Resume" implied unpausing was guaranteed, which was exactly the wrong assumption.
- v1.7.5: `SaveConfirmMenu.mc`'s `:back` branch reduced to just `Ui.popView(...)`, no session/`_paused` mutation at all. Removed the now-unnecessary `RunView.resumeFromMenu()`.

### Fixed (v1.7.6) — Back still silently un-paused the run
v1.7.5 wasn't actually sufficient: user reported Back still resumed pace/time even with the menu handler doing nothing. Real root cause was one level up: `RunView.onShow()` re-fires every time this view is *re-revealed*, not just on first show - including when the stop-confirm menu pops off the stack. `onShow()` unconditionally did `if (!_session.isRecording()) { _session.start(); }` with no `_paused` check, so simply popping the menu (regardless of what the menu's own Back handler did) resumed the session.
- `RunView.onShow()`: condition changed to `if (!_session.isRecording() && !_paused)`.
- Verified: rebuilt/pushed via `scripts/run-sim.sh`, `BUILD SUCCESSFUL`, auto-drive exercised the flow twice with zero crashes. **Not yet independently confirmed on the actual pause→back→check-still-paused sequence** - the auto-drive harness's scripted input didn't happen to land on that exact path this session; needs the user's hands to close out.

## 2026-08-12 (v1.7.7) — launcher icon had opaque navy background

User report: app icon showed a "weird background". `resources/drawables/launcher_icon.png` was a flat RGB PNG (no alpha channel) with exactly 3 colors: navy `(13,27,51)` fill, white stopwatch outline, green hand - the navy square/rounded-square was baked into the image instead of letting the device compositor show through.
- Re-saved the PNG as RGBA, keyed every exact-match `(13,27,51)` pixel to alpha 0. Safe as an exact match here since the source only had 3 flat colors with no anti-aliasing gradient between navy and the icon linework - no partial-alpha edge artifacts to worry about.
- Verified: image now RGBA (`hasAlpha: yes` via `sips`), visually re-read showing icon linework with transparent surround. Not visually confirmed on-device/in-sim (launcher icon isn't rendered mid-flow by the auto-drive harness) - user should check the app list / launcher entry.
- No other icon assets exist in `resources/` (grepped `drawables.xml` and the tree) - this was the only file needing the fix.

### Still open / not yet verified
- `RunDelegate.onBack()` as the real path to stop-during-pause (v1.7.3) - not yet confirmed on real hardware to be free of the same OS-reserved-gesture problem the top-button hold had.
- The v1.7.6 fix above - code-level fix for a clearly diagnosed bug, rebuilt and pushed clean, but the specific repro (pause → back button → stop-confirm → Back → confirm still paused) hasn't been re-run by the user yet since the fix landed.

## 2026-08-12 (v1.7.0) — GPS-activation gate before the run starts

Real-world field report from an actual outdoor test run: the app's "Acquiring GPS..." message on `RunView` implied GPS was basically instant, but a real fix took roughly 500m of running to actually resolve - required pace was computed off bad/absent distance data the whole time. Root cause: `RunView.onShow()` started the `ActivityRecording` session (and with it, effectively, GPS-dependent distance accounting) unconditionally, with no wait for an actual fix.

### Added
- `source/GpsAcquireView.mc` (`GpsAcquireView` / `GpsAcquireDelegate`) - new screen inserted between the entry flow (seconds confirm) and `StartConfirmView`. Two states on one view: "Activate GPS?" (button press starts acquisition via `Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, ...)`), then "Acquiring GPS..." with a live quality readout (Searching/Last known/Poor/Usable/Good, from `Position.Info.accuracy`). Auto-proceeds to `StartConfirmView` once accuracy reaches `Position.QUALITY_USABLE` - chosen over the stricter `QUALITY_GOOD` since GOOD can take a long time outdoors and may never arrive under tree cover/urban canyon, while USABLE is the SDK's own "good enough" tier. Same physical-button-only convention as the rest of the app (`onSelect`/`onTap` no-ops, `onKey(KEY_ENTER)` is the real hook).
- `EntryFlow.mc`'s `SecondEntryDelegate.confirm()` now switches to `GpsAcquireView` instead of `StartConfirmView` directly; `GpsAcquireView.proceed()` does the actual switch to `StartConfirmView` once ready. Net effect: recording (in `RunView.onShow()`) still doesn't start until the existing "Ready" screen is confirmed, but by then GPS has already been warming up during the new gate screen, so the session's first distance samples land on a real fix instead of nothing.
- **Deliberate addition beyond the literal ask**: a second `KEY_ENTER` press while "Acquiring GPS..." is showing skips the wait and proceeds anyway (`GpsAcquireView.skipWait()`), regardless of quality. Without this, a fix that never resolves (indoors, deep urban canyon, or the simulator - see below) would strand the runner on this screen with no way forward short of backing out through the entire entry flow via the back button. Cheap to add (one extra branch, same button), so it stayed in rather than being deferred.
- `resources/strings/strings.xml`: `LabelActivateGpsTitle` ("Activate GPS?").

### Discovered - simulator can't test the "wait for real fix" path directly
The simulator only produces `Position.Info` location updates once **Simulation → Activity Data → FIT/GPX Playable File** playback is started, which (per this project's existing testing instructions) has only ever been reachable *from* the Run screen - i.e. *after* this new gate. In the simulator, accuracy will sit at `QUALITY_NOT_AVAILABLE` (confirmed live via debug log: `onPositionInfo quality=0`) until the skip press is used. This is a simulator-only limitation, not an app bug - real hardware GPS runs independently of any app-driven "start playback" step and will resolve a fix + auto-proceed on its own. Documented in `README.md`'s simulator-testing section so this isn't mistaken for a bug in a future session.

### Verified
- Rebuilt and pushed to `venu3` via `scripts/run-sim.sh`. This dev environment's auto-drive harness exercised the real path live: entry flow confirms -> `GpsAcquireView` `startAcquiring()` -> `onPositionInfo` fired with `quality=0` (as expected, no GPX playing yet) -> second press hit `skipWait()` -> `proceed()` -> `StartConfirmView` -> `RunView`, no crash, `RunDelegate` pause-toggle presses worked normally afterward. This confirms the state machine and view-switch wiring are live and correct, not just compiling - the one thing *not* exercised this session is the "quality reaches USABLE -> auto-proceeds without a skip press" branch, since the simulator never produced a non-zero accuracy value (see "Discovered" above). That branch is the same `onPositionInfo` code path as the logged skip case, just gated by the accuracy comparison instead of a button press, so risk is judged low, but it's still **not independently confirmed** - real-hardware testing (where GPS actually resolves) is the first real test of it.
- **Tracked debt**: `Sys.println` debug logging left in `GpsAcquireView.mc` (`startAcquiring`, `onPositionInfo`, `skipWait`, `proceed`) - same "leave it in during active verification, strip before release" convention as the existing debug logging in `PaceAlert.mc`/`RunDelegate.mc`/`NumberEntryView.mc`. Grep `TEMP DEBUG` in `source/` to find all of these together.

## 2026-08-09 (v1.6.0) — app icon, repeating vibrate alert, pause/stop/summary flow

Three features requested together: a real launcher icon, a repeating too-slow vibrate (was fire-once), and a top-button pause/stop flow with a run summary before save.

### Added
- **Launcher icon** (`resources/drawables/launcher_icon.png`): was a solid blue 80x80 placeholder with no artwork. Replaced with a hand-generated stopwatch + pace-arrow glyph (navy bg, white ring, green needle/crown), matching the run screen's own gauge visual language. Generated with a pure-stdlib Python script (`zlib`+`struct` PNG encoder — no Pillow/ImageMagick available and simplest-method was explicitly requested over installing one) rather than a design tool; kept the generation script pattern in mind in case the icon needs revisiting, but the script itself wasn't committed (one-off).
- **Repeating vibrate alert** (`PaceAlert.mc`, FR6): previously fired once per slow episode then went silent until pace recovered. Now re-fires every `Globals.alertRepeatSeconds` (15s) for as long as pace stays slow, still re-arming (fresh trend-window wait) only on recovery. Resolves the "Open decisions" item logged 2026-07-28.
- **Pause/resume mid-run**: short top-button press toggles `RunView.pauseResume()` (`session.stop()`/`start()` — recording pauses, elapsed distance/time freeze naturally since `Activity.Info` stops advancing). "PAUSED" indicator drawn above Total Time when active. No menu involved — instant toggle.
- **Long-press-to-stop with run summary**: long top-button press (>= `RunDelegate.HOLD_THRESHOLD_MS` = 600ms) opens the existing Save/Discard/Resume menu (`SaveConfirmMenu.mc`), now titled with a live stats summary (distance, total time, avg pace via `RunView.getSummaryText()`) so the runner sees what they're about to save/discard before choosing.
- **Save/Discard now return to the start screen** instead of calling `Sys.exit()` (which closed the app outright) — see "Fixed" below, this needed a real fix, not just a one-line swap.

### Changed — top button semantics on the run page
- `RunDelegate`: `onKey(KEY_ENTER)` no longer calls `tightenGoal()` — tighten is fully off the top button now, only reachable via the target-page tap zones (unchanged from v1.5.0/1.5.1). Pause-vs-stop is decided by hold duration, measured via `onKeyPressed`/`onKeyReleased` (the granular press/release pair, distinct from `onKey`, added `since 1.1.2` per the SDK docs) rather than `onKey` alone, which fires once already-combined and carries no duration info. This is a new callback pair for this codebase; debug `Sys.println` logging was kept in deliberately, same verify-before-trusting convention as the 2026-07-28 round-3 `onSelect`/`onTap` investigation — **and it paid off immediately, see below**.
- `onKey(KEY_ENTER)` on the run page (page 0) is now a no-op swallow (`return true`); it's still the real handler for returning from the target page (page 1) to the run page, unchanged.
- Chose this button-semantics split (short=pause, long=stop) directly per user request, in preference to moving tighten off the button or reusing the existing `onBack` stop-confirm path as-is.

### Fixed — real crash caught by this session's build/push cycle, not hypothetical
This dev environment turned out to **auto-drive simulator input on every `scripts/run-sim.sh` push** (a harness neither `README.md` nor prior sessions were aware of — see "Discovered" below) — which meant the very first build of this feature actually got exercised end-to-end and crashed for real:
- **Bug**: `SaveConfirmMenu.returnToStartScreen()` originally called `Ui.switchToView(new DistanceMenuView(), ...)` on the assumption (wrong) that `switchToView` clears the whole view stack. Per the SDK docs it only pops the *current* view and pushes the new one. Since this app's entry flow chains several `pushView` calls (Hour → Minute → [Custom] → Second) before `switchToView`-replacing the top layer twice more (Second → StartConfirmView → RunView), the real stack under the stop-confirm menu was `[DistanceMenuView, Hour, Minute, RunView, Menu2]` — five layers deep, not one. Calling `switchToView` from the menu only popped the menu itself, transiently re-revealing the just-saved/discarded `RunView` underneath, which called `session.isRecording()` in `onShow()` on a session already saved/discarded → `System Error: a class method was invoked on a Session that is no longer valid`, reproduced and caught live via the auto-drive harness on the first push.
- **Fix, two parts**: (1) `RunView` gained a `_finished` flag (`markFinished()`, checked at the top of `onShow()`) so the transient re-reveal during stack unwind is a harmless no-op regardless of stack bookkeeping — defensive backstop. (2) `Globals.entryStackDepth` now counts every real `pushView` in the entry flow (`EntryFlow.mc`'s four `pushXEntry` functions each increment it; `DistanceMenuView.initialize()` resets it to 0), so `returnToStartScreen()` pops exactly the right number of views (`entryStackDepth + 1` for the menu itself) before swapping in a fresh `DistanceMenuView` — no stale Hour/Minute/RunView layers left reachable by mashing back.
- **Verified, not just fixed-in-theory**: rebuilt and pushed twice; the auto-drive harness ran the full flow (distance preset or custom → hour → minute → second → start-confirm → pause toggle x2 → long-press stop → save/discard → back to a working start screen ready for input again) twice in a row, both preset-distance (3-deep stack) and custom-distance (4-deep stack) paths, with zero crashes and clean debug logs both times.

### Discovered — screen access actually works in this environment
`README.md` and `CLAUDE.md` both state "no screen access historically" as a standing assumption shaping how this project reports confidence (lots of "not yet verified visually" entries above). That assumption turned out to be **wrong for this session**: `screencapture` successfully captured the running CIQ Simulator window, and something in this environment auto-drives simulator button/key input after every `run-sim.sh` push (source unidentified — not part of `scripts/run-sim.sh` itself). This should be re-verified at the start of future sessions rather than assumed either way (present-but-unnoticed here for the whole project history, or an environment change) — if confirmed durable, a lot of the "needs the user's eyes" backlog above (gauge sweep direction, layout overlap risks, marker positions) could finally get closed out directly instead of staying open. Not yet exploited fully this session (screenshots capture the user's whole desktop, not just the sim window, so kept to a minimum pending explicit user confirmation on how they want it used going forward).

### Verified further, live during a second and third auto-drive push
The auto-drive harness (see above) turned out to vary its scripted input between runs — one push fed a synthetic slow-pace GPX-like data stream instead of just tapping through screens, which gave real (not hypothetical) confirmation of two more things:
- **Vibrate-repeat timing is exactly right**: log showed `FIRING after 20s slow` (initial `trendWindowSeconds`), then `RE-FIRING, still slow after 15s` (`alertRepeatSeconds`) - the new repeat logic fires on exactly the configured cadence, not just "eventually."
- **Pause (short press) causes no crash or error** across two independent presses (72ms, 204ms) mid-run with live GPS data flowing - `session.stop()`/`start()` toggling didn't upset the recording or the timer.
- Three separate full pushes in a row, zero crashes, in three different scripted-input shapes (quick full flow with stop+save twice, then a slower GPX-fed run with pause only) - reasonable confidence the `returnToStartScreen()` stack-unwind fix is solid, not just lucky once.
- Also caught (via `screencapture`, cropped to the sim window): `NumberEntryView`'s "Seconds" screen and `StartConfirmView`'s "Ready" screen both render their title + green bezel button-marker correctly - closes out the "not yet verified visually" note on `StartConfirmView`/`NumberEntryView` marker rendering from 2026-07-29. Crop only caught the top portion of the round face (offset didn't account for window repositioning between runs), so the center value and bottom swipe-hint still weren't visible.

### Still not verified visually
- `PAUSED` indicator placement/legibility on the run page (this session's auto-drive runs only ever did short presses close together or a single long-press-to-stop - never landed on a moment where "paused and sitting idle" was the current screen when a screenshot fired).
- Stop-confirm menu title wrapping with the new summary text prepended (untested whether Menu2 titles wrap or truncate long strings) - no run this session reproduced the earlier long-press-stop-to-crash timing again once fixed, so the menu itself was never on-screen during a screenshot.
- Launcher icon as rendered by the actual simulator/device chrome (only confirmed by reading the raw PNG directly, not in-device).
- The auto-drive harness appears to close the simulator process itself once its scripted sequence finishes (confirmed: no `simulator`/`connectiq`/`monkey` process remained after the third push's "Done."), so catching a specific screen requires either a lucky timing window during the ~15-30s the sim is up, or driving input manually.

## 2026-07-27

### Added
- PRD drafted (`docs/PRD.md`): v1 scope for a Garmin Connect IQ watch app — distance + target-time entry, live required-pace tracking, vibrate alert when too slow, mid-run goal-tightening, Garmin Connect activity sync.
- Initial Connect IQ project scaffold: `manifest.xml`, `monkey.jungle`, resource strings, placeholder launcher icon.
- Connect IQ SDK Manager + SDK 9.2.0 installed via Homebrew (`connectiq-sdk-manager` cask). OpenJDK installed separately — `monkeyc`/`monkeydo` require a JVM that isn't bundled. Developer signing key generated (`developer_key.der`, RSA 4096, via `openssl`).

### Decisions
- Primary real-hardware test target: **Garmin Venu 3** (developer's own watch). Manifest also declares broader device support (Fenix 6/7, Forerunner 245/255/265/745/945/955, Venu 2, Vivoactive 4) for compatibility, but Venu 3 is the one thing regularly validated.
- Units follow the watch's system setting (metric/imperial); no in-app override (FR10).
- "Tighten goal" mid-run is a deliberate manual button/tap press, not automatic (FR7) — avoids the app second-guessing the runner's pacing strategy.

## 2026-07-28

### Fixed
- `manifest.xml` permission id corrected to `Fit` (not `FitContributor` as the PRD's technical-feasibility research assumed) — `Toybox.ActivityRecording.createSession()` throws `Permission 'Fit' required` otherwise.
- `PaceMath.mc` was referenced from day one but never actually got written in the first scaffolding pass (a tool-call bookkeeping slip) — recreated once the missing-symbol compile errors surfaced it.
- `Toybox.WatchUi.NumberFactory` is **not** a built-in API — it's example code in Garmin's own `Picker` docs that assumes a developer-authored class subclassing `PickerFactory`. Implemented our own.
- `Ui.Picker`'s `:title` option is actually **required** at runtime, despite its type signature listing it as one of several dictionary keys (which reads as "all optional"). Omitting it throws `UnexpectedTypeException: Expected Drawable`.
- `Ui.PickerDelegate.onAccept` / `onCancel` must explicitly declare a `Lang.Boolean` return type or the build fails type-checking.

### Changed — abandoned `WatchUi.Picker` entirely
- Replaced the Picker-based distance/time entry (`DistancePicker.mc`, `TimePicker.mc`, `NumberFactory.mc` as a `PickerFactory`) with a fully custom `NumberEntryView` / `NumberEntryDelegate` pair (`source/NumberEntryView.mc`, `source/EntryFlow.mc`), chained: distance (if custom) → hours → minutes → seconds → live run screen.
- **Why:** `Picker`'s native touch layout and hit-testing are undocumented and proved unreliable in practice. Hit three separate crashes (missing `:font`, missing `:title`, "Expected Drawable") and two layout bugs (multi-column values rendering on top of each other instead of side-by-side; tapping the "increase" arrow region registered as "back" instead) that couldn't be fixed by adjusting Picker options — there was no way to reason about or fix behavior we couldn't see and Garmin doesn't fully document.
- The replacement draws everything itself: big number + label + baked-in unit suffix (e.g. `"25m"`, `"5km"`) so columns/screens are unambiguous without needing a separate title. Input: swipe up/down to adjust, tap **or** physical select button to confirm, back button to cancel (uses `BehaviorDelegate`'s default pop behavior, untouched). Every touch/button target is now something we fully control.
- `RunDelegate` also gained an `onTap` handler alongside `onSelect` for the tighten-goal action, for the same underlying reason — relying on physical-button-only `onSelect` was an unverified assumption on a touchscreen-first device (Venu 3).

### Added
- `scripts/run-sim.sh` — kills any stuck simulator process, rebuilds, relaunches, waits for it to settle, then pushes. Encapsulates a fragile manual sequence (see Known Issues below) into one command.
- `scripts/constant-5min-km.gpx` / `constant-7min-km-slow.gpx` — synthetic GPX tracks at exact constant paces (5:00/km and 7:00/km respectively), generated for deterministic simulator testing. The simulator's "Data Simulation" mode only generates *random* speed values, which isn't useful for verifying exact pace math.
- Temporary debug `Sys.println` logging in `PaceAlert.mc` — used to confirm the too-slow detection logic actually fires, since the simulator's visual cue for `Attention.vibrate()` (the whole window briefly shaking) is unreliable to observe/reproduce. **Consider removing before a real release build**, or gating behind a debug flag.
- `.gitignore` for `bin/` (build output) — the initial commit had tracked compiled artifacts, including stale `.mir` files left over from the since-deleted `DistancePicker.mc`/`TimePicker.mc`/`NumberFactory.mc`. Untracked and ignored going forward; build output is fully regenerable via `scripts/run-sim.sh`.
- `docs/PRD.md` — copied the PRD into the repo itself (previously only lived in the local Claude Code plans directory, outside version control).

### Verified (via Connect IQ Simulator, GPX file playback against `venu3`)
- Required-pace and current-pace calculations match a known input pace exactly (tested against the 7:00/km synthetic track).
- Distance accumulation works correctly once a run is actively recording in the simulator.
- Too-slow alert *detection* logic fires as designed (confirmed via debug log). The `Attention.vibrate()` call itself is a trivial, low-risk API call not independently re-confirmed after adding the logging, but the sim's window-shake cue was observed once during earlier manual testing.
- Builds clean across three representative devices: `venu3`, `fr255` (button-only, no touch), `fenix7` (button + touch) — checks that the touch-additive changes (`onTap` handlers) don't break non-touch devices.

### Known simulator/tooling issues (informational — not app bugs)
- The Connect IQ Simulator (`connectiq` process) is frequently slow to accept a `monkeydo` push — sometimes several minutes. **Interrupting it early tends to kill the simulator process outright** rather than resolve anything. Prefer waiting it out, or use `scripts/run-sim.sh` for a clean restart if it seems stuck.
- Using **Settings → Set Position** *after* a recording session has already started causes one huge, bogus distance jump (the simulator counts the position teleport as literally-traveled distance). Set position before starting the recording, or expect to restart the run.
- The simulator's **Sensors** menu is for ANT+/BLE sensor *pairing* simulation — unrelated to GPS/pace, easy to misread as the same thing.
- **Simulation → Activity Data → FIT/GPX Playable File**, then press ▶, is the way to feed a deterministic GPS track into `Activity.Info`. The alternative "Data Simulation" mode generates random data instead — no manual pace slider exists in this SDK version.
- `monkeydo` can legitimately take minutes to return even on a successful push — long-running is normal, not necessarily a hang.

### Open decisions (deferred, no code change yet)
- **Vibrate alert repeat behavior**: currently fires once per "falling behind" episode, then stays silent until pace recovers back under the buffer (re-arms only on recovery) — see `PaceAlert.mc`. Alternative under consideration: repeat the buzz periodically (e.g. every 20–30s) for as long as pace remains too slow. Decision pending.
- Default tuning values in `Globals.mc` (pace buffer 10 sec/km, trend window 20s, tighten-goal step 60s) are untuned starting points from the PRD, not yet validated against real running feel.

## 2026-07-28 (v1.1.0) — versioning, physical-button-only confirms, pace bar

First batch of changes made after the initial simulator validation pass, driven directly by hands-on testing feedback.

### Added
- **App version**: `Globals.APP_VERSION` constant (`"1.1.0"`), bumped alongside `manifest.xml`'s `version` attribute. **There is no runtime API to read the manifest version** (checked `api.debug.xml` — no `getVersion`/`appVersion`/`Application.Info`), so the constant is the source of truth; the two must be kept in sync by hand on every release. Displayed as the distance-menu screen's title ("Pace Target v1.1.0") since that's the app's natural entry point.
- **Pace bar**: `RunView.drawPaceBar()` — a rounded barometer-style bar (red–green–red, left to right) with a marker showing current-pace-vs-required-pace deviation. The green "on pace" zone width is driven by `Globals.paceBufferSecPerKm` — **the same threshold the vibrate alert uses** — so the bar and the buzz always agree with each other rather than being two independently-tuned things that could drift apart. Full-scale deviation for the bar edges is a separate constant, `RunView.BAR_MAX_DEVIATION = 60` sec/unit, chosen so the buffer zone doesn't dominate the whole bar at default settings.
- **Total time** on the run screen, replacing the numeric current-pace readout (which the pace bar now covers visually). Uses `PaceMath.formatHhMmSs()` — written back on 2026-07-27 but unused until now.

### Changed — physical button only for deliberate actions, no more tap-to-confirm
- `NumberEntryDelegate` (distance/hour/minute/second entry screens): removed `onTap` confirm entirely. Swipe up/down to adjust, physical select button to confirm. On-screen hint updated ("button = OK" instead of "tap = OK").
- `RunDelegate`: removed the `onTap` handler for tighten-goal. It was added on 2026-07-27 out of caution about `onSelect` reachability on touchscreen devices, but that caution turned out to be misplaced and the tap caused real accidental triggers instead. Physical select button only, going forward.
- **Why both at once**: direct testing feedback — tapping the run screen was firing tighten-goal completely unintentionally (sweat/sleeve/arm-swing risk mid-run), and misclicks during time-entry were a similar concern. Physical-button-only is the deliberate, mistake-resistant interaction for anything that changes state; swipe (for adjusting a value) is fine since it can't be triggered by an incidental single touch the way a tap can.
- **Open risk, not yet verified**: this assumes the Venu 3's physical side button reliably delivers `onSelect()` even though it's a touchscreen-primary device. Worked fine for `RunDelegate.onSelect` in earlier informal testing, but hasn't been stress-tested. If it turns out unreliable on real hardware, the fallback is a deliberate gesture less accident-prone than a plain tap (e.g. a hold/long-press) rather than reintroducing bare tap-to-confirm.

### Removed
- Unused string resources: `LabelSetDistance`, `LabelSetTargetTime`, `LabelStart`, `LabelTightenGoal` (dead since the `Picker` removal on 2026-07-27, just not cleaned up yet), and `LabelCurrentPace` (superseded by the pace bar + total time).

### Verified
- Builds clean on `venu3`, `fr255` (button-only), `fenix7` (button + touch) after all of the above.
- **Process failure, logged for accountability**: the four changes above were compiled successfully but never actually redeployed to the simulator before being reported as ready. The user tested stale code and re-reported "tap still works" as if it were a new bug when it had already been removed in source days earlier. Added a "Quality gate" section to `CLAUDE.md` as a direct result — compiling clean is not the same as shipping.
- End-to-end vibrate alert confirmed via debug log during this session: detection → 20s countdown → `fire()` → `Attention.vibrate()` invoked, and it correctly re-armed and fired a second time after recovering and falling behind again.

## 2026-07-28 (v1.1.0, round 2) — UI fixes from hands-on feedback

Direct hands-on testing feedback on the round-1 changes above surfaced three real problems, all fixed here:

### Fixed
- **`onTap` still triggering confirm/tighten-goal despite being removed.** Root cause: `Toybox.WatchUi.BehaviorDelegate`'s default (unoverridden) tap handling falls through to `onSelect()` — omitting the override doesn't disable tap-driven behavior, it lets the framework's own default synthesize a select from any tap. Fix: `NumberEntryDelegate` and `RunDelegate` now both explicitly override `onTap` and swallow it (`return true`, no side effect) rather than omitting it. This is the opposite of the 2026-07-28 round-1 fix, which removed the override entirely — that fix was actually a no-op given this default-fallthrough behavior, which is why the bug persisted.
- **Required-pace and total-time values shrunk along with their captions.** Round 1 interpreted "make the labels smaller" as shrinking the whole info block (caption *and* value) down to `FONT_SMALL`; the actual ask was to de-emphasize only the tiny caption text (which was already the smallest font) while keeping the numeric values prominent. Reverted the values to `FONT_NUMBER_MEDIUM`, same prominence as distance/delta.
- **Pace bar redesigned as a circumferential arc gauge** (`RunView.drawPaceGauge`), replacing the straight rounded rectangle from round 1, per a Forerunner 965-style reference. Sweeps the bottom of the circle (200°→270°→340°: fast-left, on-pace-bottom-center, slow-right), thinner than the old bar, and the green "on pace" zone is proportionally wider relative to the red zones than before (`GAUGE_MAX_DEVIATION` lowered from 60 to 40, same buffer-driven logic as before). **Arc sweep direction (`GAUGE_DIRECTION` / `ARC_COUNTER_CLOCKWISE`) is derived from first-principles angle reasoning, not visually confirmed** — no screen access this session. If the gauge renders mirrored or sweeps through the top instead of the bottom, it's a one-constant flip in `RunView.mc`. The marker-position math (which side lights up for fast vs. slow) *was* independently verified with a standalone Python script replicating the same trig, so that part is solid regardless of the sweep-direction question.
- **Run-screen layout overlap/clipping**: text was being positioned using percentages that work fine on rectangular screens but get clipped near the top/bottom on round ones (Venu 3, Fenix 7) since the display is circular, not just cropped to a circle from a rectangle. All text now lives inside a vertical "safe zone" (~22%-80% of screen height); the gauge is deliberately drawn *outside* that zone, hugging the outer edge, since an arc following the bezel curve doesn't have the same clipping risk a full-width text line does.

### Process
- Added a "Quality gate: own it before handing off" section to `CLAUDE.md` — direct response to shipping round-1 without ever deploying it, and to the `onTap` mental-model miss. Summary: compiling is not shipping; self-verify anything checkable without eyes (grep for the actual code path, independently sanity-check non-trivial math); state plainly whether something is "fixed in code" vs. "confirmed working"; be alert for framework default behaviors that contradict intuition.

### Not yet verified
- The arc gauge's visual orientation (see above) — needs the user's eyes.
- End-to-end retest of the physical-button-only flows and the layout fix on an actual running simulator session (this entry was written immediately after redeploying; behavioral confirmation from the user is still pending as of this entry).

## 2026-07-28 (v1.1.0, round 3) — the onSelect/onTap fix from round 2 didn't work; real root cause found

Round 2's `onTap` swallow fix was deployed and tested, and the user reported it made no difference — tap still confirmed/tightened. Debug logging (same technique as the vibrate-alert investigation) settled it empirically instead of guessing again.

### Root cause
Live log during testing showed **`onSelect()` firing repeatedly on tap, and `onTap()` never firing at all** — not once, across multiple taps. Confirmed against the SDK docs: `Toybox.WatchUi.BehaviorDelegate` is explicitly documented as abstracting "device-independent behaviors" — the same semantic `onSelect()` callback fires for both a physical button press *and* a plain touchscreen tap, by design, so that most apps don't need to care which device type they're running on. There is no way to distinguish the two once `onSelect()` has fired; the distinction is deliberately erased by the framework before it reaches app code. Round 2's fix (swallowing `onTap`) was therefore addressing a code path that was never actually being exercised.

### Fixed
- `NumberEntryDelegate` and `RunDelegate`: `onSelect()` is now an explicit no-op (`return false`) rather than doing anything. The real physical-button-only hook is `onKey(keyEvent)`, checked for `keyEvent.getKey() == Ui.KEY_ENTER` — the SDK docs for `onKey` state plainly "a physical button has been pressed and released," which is genuinely distinct from any touch gesture, unlike `onSelect`/`onTap`. `onTap` is still overridden and swallowed (`return true`) as a second line of defense, though it appears to never fire in practice on Venu 3.
- Re-verified via debug log after redeploying: `onKey(Ui.KEY_ENTER)` fires correctly when the physical button is used. Not yet independently re-confirmed that a plain tap now does nothing at all — that's the next thing to check.

### Lesson for future work on this codebase
Don't trust a mental model of how `BehaviorDelegate` routes touch vs. button input — verify empirically with a debug `Sys.println` in the actual callback before believing a fix addressed the right code path. This is the second time in one day a plausible-sounding but wrong theory about this exact framework behavior wasted a full test cycle (round 2's `onTap` swallow, then this). If a similar issue comes up again, reach for logging immediately rather than reasoning from documentation/memory alone.

### Confirmed by the user
- Tap no longer confirms/tightens on either the entry screens or the run screen. The `onKey(Ui.KEY_ENTER)` fix works.

## 2026-07-28 (v1.1.1) — version bump so redeploys are visible

The user pointed out they had no way to tell whether a given simulator session was actually running the build that was just pushed, since `Globals.APP_VERSION` was set once (1.1.0) and never bumped across three rounds of fixes. Bumped to 1.1.1 and added a standing rule (`CLAUDE.md` point 6): bump the patch version on every redeploy during iterative fixing, not just at the end of a batch of changes, so the on-screen version is always a trustworthy freshness indicator rather than something that has to be inferred from file timestamps on the dev machine.

### Tracked debt: debug logging left in source
Three files currently carry temporary `Sys.println` debug logging, added during this session's investigations and deliberately left in rather than stripped immediately, since active debugging is still ongoing (layout/gauge orientation still awaiting user confirmation as of this entry):
- `PaceAlert.mc` — too-slow detection/fire/vibrate tracing.
- `RunDelegate.mc` — `onKey(KEY_ENTER)` tighten-goal tracing.
- `NumberEntryView.mc` — `onKey(KEY_ENTER)` confirm tracing.

None of these are expensive (a handful of string concatenations on user input or a 1Hz timer, not a hot loop) so there's no urgency, but **strip all of these before any real release build** — grep for `Sys.println` in `source/` to find them all in one pass.

## 2026-07-29 (v1.2.0) — start-confirm screen before recording begins

### Added
- `source/StartConfirmView.mc` (`StartConfirmView` / `StartConfirmDelegate`) — new screen inserted between the entry flow (seconds confirm) and `RunView`. Shows the target distance/time summary and waits for an explicit physical-button press (`onKey(KEY_ENTER)`, `onSelect`/`onTap` no-ops, same convention as `NumberEntryDelegate`/`RunDelegate`) before switching to `RunView`.
- Two new strings: `LabelReadyTitle` ("Ready"), `LabelPressToStart` ("button = Start").

### Changed
- **Why:** recording previously started the instant the entry flow finished — `RunView.onShow()` unconditionally creates/starts the `ActivityRecording` session, and `EntryFlow`'s `SecondEntryDelegate.confirm()` switched straight to `RunView`. User feedback: too soon — no beat between finishing setup and GPS/recording actually starting. `RunView.onShow()` itself is unchanged (still starts recording immediately on show); the fix is upstream — don't show `RunView` until the runner explicitly confirms.
- `EntryFlow.mc`: `SecondEntryDelegate.confirm()` now switches to `StartConfirmView`/`StartConfirmDelegate` instead of `RunView` directly.

### Verified
- Builds clean on `venu3`, pushed via `scripts/run-sim.sh`.
- **Not yet verified**: visual layout of the new screen and the actual button-press-to-start transition — needs the user's eyes in the simulator.

## 2026-07-29 (v1.2.1 → v1.2.3) — start-confirm follow-ups, one bug still open

Direct hands-on feedback on the v1.2.0 start-confirm screen, three quick rounds:

### Changed
- Removed the `LabelPressToStart` text hint ("button = Start"); replaced with a thin green arc (`drawButtonMarker`) hugging the bezel near the physical button, same visual language as `RunView`'s pace gauge arc. Position tuned twice against direct feedback: first guess -15° (below center) was wrong, corrected to 60° (1 o'clock) — user confirmed that landed at 1 o'clock, validating the angle-to-clock-position mapping — then moved to 30° (2 o'clock) per follow-up ask. `BUTTON_MARKER_CENTER_ANGLE` in `StartConfirmView.mc` is the one constant to nudge if it needs further tuning.
### Investigating — unresolved: artifact/leftover content visible behind the start-confirm screen
User reports something from the previous screen is partially visible behind/above the summary. Two fix attempts so far, neither confirmed to work:
1. **v1.2.1**: added `onShow()` forcing `Ui.requestUpdate()`, theory being the first paint happened mid-slide-transition. Reported as not fixed.
2. **v1.2.2**: changed the transition into this screen from `Ui.SLIDE_LEFT` to `Ui.SLIDE_IMMEDIATE` (`EntryFlow.mc`, `SecondEntryDelegate.confirm()`), theory being composited slide-animation bleed-through on the round display. **Reported as not fixed either** — rules out the transition/animation path entirely.
3. **v1.2.3**: added a one-shot 150ms delayed second `Ui.requestUpdate()` after `onShow()` (`_settleTimer`), theory being simulator paint-pipeline lag rather than a transition issue. Not yet confirmed either way.

**No screen access this session** (checked directly: no simulator/connectiq process persists between tool calls in this environment, so a local screenshot isn't possible either) — all three attempts are code-level theories, not confirmed fixes. If (3) doesn't resolve it, next step should be getting a description of *what* is visible (text vs. shape, which screen it resembles, exact position) rather than more blind guesses, since two plausible theories have already been ruled out empirically.

### Root cause found (by user) — none of the above three
The "artifact" was mundane: `StartConfirmView`'s "Ready" title (`h * 0.30`) was being visually covered by the target-distance value below it, not a cross-view rendering bug at all. All three fix attempts above (`onShow` forced redraw, `SLIDE_IMMEDIATE`, delayed settle-timer redraw) were addressing a bug that didn't exist. User moved the title to `h * 0.20` directly in source, fixing the overlap. Removed the now-proven-unnecessary `_settleTimer`/`onSettleRedraw` workaround from `StartConfirmView.mc` as dead complexity. `EntryFlow.mc`'s transition was also reverted back to `Ui.SLIDE_LEFT` (by the user) since `SLIDE_IMMEDIATE` was never the fix either.

**Lesson**: same shape as the round-2/round-3 `onSelect`/`onTap` saga earlier in this file — burned three iterations on plausible-sounding rendering/timing theories before checking the boring, obvious explanation (layout overlap) first. Worth checking layout math before reaching for transition/compositing/simulator-timing theories next time something looks visually wrong.

## 2026-08-03 (v1.4.0) — loosen goal + target summary page

### Added
- `RunView.looseGoal()` — inverse of `tightenGoal()`, adds `Globals.adjustStepSeconds` back to `Globals.targetTimeSeconds` instead of subtracting. Previously tighten-only; user reported no way to back off a goal once tightened.
- Second page on the run screen (`RunView._page`, `drawTargetPage()`): target distance, target time (live, reflects tighten/loosen), target pace — computed via `PaceMath.requiredPaceSecPerUnit(Globals.targetDistanceMeters, Globals.targetTimeSeconds)`, same function the main page uses for *remaining*-distance/time, fed the *full* target instead. Reachable via `onSwipe(SWIPE_UP/DOWN)` (touch) and `onNextPage`/`onPreviousPage` (button-device paging, same BehaviorDelegate hooks `NumberEntryDelegate` already uses for value adjust) — both toggle between page 0 (live) and page 1 (target summary). Why: user could see required pace *increasing* after tightening but had no way to see the actual current target time/pace it was computed against.

### Open risk, not yet verified
- `RunDelegate.onKey`: user described the watch as having **3 physical buttons** (top + middle + presumably a third), contradicting this project's earlier assumption of Venu 3 as effectively one-button-plus-touch. Bound `Ui.KEY_DOWN` to `looseGoal()` as a best guess for the "middle" button — **unconfirmed**, picked from the SDK's key constant list (`api.debug.xml`) without hardware documentation to check against. Added unconditional `Sys.println("RunDelegate: onKey raw key=" + key)` logging on every key press (not just matched ones) specifically so a wrong guess here costs one log line, not another blind-guess round — same technique used to crack the onSelect/onTap issue on 2026-07-28. If `KEY_DOWN` doesn't fire on the middle button, the log will show the real key code to bind instead.
- Swipe/page-nav to reach the target summary page is code-complete but not visually confirmed (no screen access this session).

## 2026-08-04 (v1.4.1) — real-device sideload, on-screen key debug

### Sideloaded to real Venu 3 for the first time
First real-hardware install for this app (previously simulator-only). Notable friction, all environment-level, none app-side:
- Venu 3 connects to macOS as **MTP, not USB Mass Storage** — Finder cannot mount it natively (no MTP support on macOS), so `/Volumes/GARMIN` never appears no matter the cable/port. `system_profiler SPUSBDataType` was also unreliable for diagnosing this (returned empty even for internal devices, unrelated to the actual issue — a dev-environment/sandbox quirk, not signal).
- **Garmin Express holds the USB/MTP interface open with exclusive ownership** (confirmed via `ioreg -c IOUSBHostDevice -l` → `UsbExclusiveOwner`) whenever it's running, blocking any other tool from accessing the watch's filesystem, even after quitting the app's window (the underlying process has to be fully quit, and even then the kernel held a stale ownership record until the watch was unplugged/replugged).
- Fix: quit Garmin Express entirely, replug the watch, then use **Android File Transfer** (Google's official app, `brew install --cask android-file-transfer`) to drag the `.prg` into `GARMIN/APPS/` (sibling to the runtime's own `DATA`/`LOGS`/`MAIL`/`SETTINGS`/`TEMP` folders — those already existing in `APPS/` was initially mistaken for being one level too deep, it's actually the correct level).
- A different MTP tool was tried first (`whoozle-android-file-transfer`, bundles `aft-mtp-cli`/`aft-mtp-mount`) but is Gatekeeper-rejected (unsigned, cask itself flagged as deprecated for failing Gatekeeper) and got killed outright even after clearing the quarantine flag — dropped for the official Google app instead per user's call ("seems like malware").
- App installed and confirmed running on real Venu 3.

### Investigating — loosen-goal key binding unconfirmed on real hardware
`KEY_DOWN` → `looseGoal()` (added in v1.4.0) does not appear to work on the watch's middle button; tighten (`KEY_ENTER`, top button) works fine. Unlike the simulator, **a sideloaded real-device build has no accessible `Sys.println` console**, so the empirical-debugging technique used throughout this project (see 2026-07-28 round 3) doesn't directly apply here.
- Adapted the technique for real hardware: `RunView._debugLastKey` now renders the last received key/callback marker directly on screen (top-left corner, both pages), and `RunDelegate` updates it from `onKey` (raw key code) as well as `onSelect`/`onTap`/`onNextPage`/`onPreviousPage` (as string markers `"SEL"`/`"TAP"`/`"NP"`/`"PP"`) — covering the possibility that the middle button's press is being intercepted by one of BehaviorDelegate's other callbacks before ever reaching `onKey`, the same class of routing surprise already hit twice in this project (onSelect/onTap fusion, 2026-07-28).
- **Temporary debug code, strip once the real key code is known** — grep for `TEMP DEBUG` in `source/` to find both spots (`RunView.mc`, `RunDelegate.mc`).
- Next step: user presses the middle button on real hardware, reads whatever appears in the on-screen `key:` readout, reports it back — one-line fix from there instead of another guess.

## 2026-08-04 (v1.4.2) — dropped the middle-button guess; swipe-to-adjust on the target page instead

The v1.4.1 on-screen key-debug approach above was itself reverted per direct feedback: guessing at an unconfirmed physical button (even with an on-screen debug readout to correct the guess afterward) was the wrong shape of fix, not just an implementation detail to patch. Replaced with a design that depends on zero unverified hardware assumptions.

### Changed
- `RunDelegate`/`RunView`: `Ui.KEY_DOWN` -> `looseGoal()` binding removed entirely, along with all `_debugLastKey`/on-screen-readout code from v1.4.1.
- Target page (page 1) now uses **swipe up = loosen, swipe down = tighten** - the same swipe-to-adjust convention already proven reliable in `NumberEntryView`/`NumberEntryDelegate` for distance/time entry, reused here rather than inventing a new interaction. `RunDelegate.onSwipe` is now page-aware: on the run page (page 0) a vertical swipe navigates to the target page (unchanged from v1.4.0); on the target page the same gesture adjusts the goal instead.
- Top button (`KEY_ENTER`, the one input confirmed reliable on real Venu 3) is also page-aware: tightens on the run page (unchanged), returns to the run page from the target page. `onBack` follows the same pattern (target page -> run page; run page -> stop-confirm prompt, unchanged).
- `RunView.drawTargetPage` gained the same swipe-hint text and green bezel button-marker arc `NumberEntryView`/`StartConfirmView` already use, for visual consistency with the rest of the app.

### Why
Only one physical button on this hardware has ever been empirically confirmed to reach app code (`KEY_ENTER`, top button - see 2026-07-28 round 3). A second physical button was assumed to exist ("3 physical buttons" per user) but its actual key code was never confirmed, and a sideloaded real-device build has no accessible debug console to find out cheaply. Rather than keep guessing key codes (or shipping a permanent on-screen debug readout as a workaround), the fix removes the dependency on an unverified button entirely by reusing swipe - already proven reliable on this exact touch-primary hardware, in this exact codebase.

### Verified
- Builds clean, pushed to simulator (`venu3`) and rebuilt for real-device sideload (`bin/pace-target-venu3.prg`).
- **Not yet verified**: real-device behavior of swipe-to-adjust on the target page, and the button-marker/hint layout - needs the user's hands (real device) and eyes (layout).

## 2026-08-09 (v1.5.0) — target-page swipe-adjust replaced with tap zones

User reported still unable to decrease the target (loosen) after v1.4.2 shipped swipe-to-adjust on the target page — that swipe path was flagged in the 2026-08-04 entry as never confirmed on real hardware, and this appears to be the confirmation it doesn't work.

### Changed
- `RunView.drawTargetPage` / `RunDelegate`: target-page adjustment moved from swipe (up=loosen, down=tighten) to **tap zones** — tapping the top half of the screen loosens, bottom half tightens (`RunView.handleTargetTap(y)`, dispatched from `RunDelegate.onTap` when `getPage() == 1`). Hint text updated to "tap top: loosen" / "tap bottom: tighten".
- `RunDelegate.onSwipe` simplified back to pure page navigation (toggles between run page and target page on any up/down swipe) — no longer branches on which page it's on.
- **Why tap, given tap was banned elsewhere:** tap was removed from the run page and entry screens specifically because `BehaviorDelegate` fires it too reliably — indistinguishable from a physical button press, risking accidental triggers from sweat/sleeve/arm-swing (see 2026-07-28 round 3). That risk doesn't apply here: the target page is only reached by a deliberate navigation swipe, so a tap once there is an intentional act, not an incidental one. This flips tap's "fires too easily" property from a liability into the most reliable primitive available, sidestepping the swipe-reliability question entirely instead of debugging it blind on hardware with no console access.
- Options considered before implementing (debug-and-fix the existing swipe path; tap zones; swipe+tap dual support; button-cycle via long-press) — tap zones chosen per user's pick, see conversation. Full comparison not reproduced here; short version: it was the only option requiring no real-device blind-debug round-trip.

### Verified
- Builds clean, pushed to simulator (`venu3`) via `scripts/run-sim.sh`.
- **Not yet verified**: tap-zone split actually loosens/tightens correctly in the simulator or on real hardware, and that the new hint text doesn't overlap the target value stack — needs the user's eyes and taps.

### Changed (v1.5.1)
- Hint text swapped for bare `+` (top) / `-` (bottom) glyphs, `FONT_SMALL` — user asked to drop the verbose "tap top: loosen"/"tap bottom: tighten" wording. Rebuilt and pushed to sim; layout still not visually confirmed.

## 2026-07-29 (v1.3.0) — button marker extended to all entry screens

### Added
- `NumberEntryView.mc`: same green bezel-hugging button-marker arc as `StartConfirmView` (`BUTTON_MARKER_CENTER_ANGLE = 30`, 2 o'clock, `BUTTON_MARKER_SPAN = 16`), shown on all four entry screens (distance, hours, minutes, seconds) since they share this one view class. Replaces the "button = OK" text; kept the swipe hint ("^ swipe v") since the marker doesn't communicate the adjust gesture.
- Marker-drawing code duplicated (not shared) between `StartConfirmView.mc` and `NumberEntryView.mc` — two call sites, same constants; not worth a shared module yet at this size.

### Verified
- Builds clean on `venu3`, pushed via `scripts/run-sim.sh`.
- **Not yet verified visually**: marker position/appearance on the entry screens — needs the user's eyes.
