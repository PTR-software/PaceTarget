using Toybox.WatchUi as Ui;
using Toybox.ActivityRecording as Record;
using Toybox.Activity as Activity;
using Toybox.Position as Pos;
using Toybox.Timer as Timer;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Application as App;
using Toybox.Math as Math;

// FR3/FR4/FR5/FR8: owns the ActivityRecording session and renders the live
// required-pace / pace-gauge / total-time / distance / delta screen.
//
// Layout: text is stacked top-down using dc.getFontHeight() so overlap is
// structurally impossible (each element's Y is the previous one's actual
// measured bottom edge, not a guessed percentage) - guessed percentages
// caused a real overlap bug once already when a font size changed without
// the surrounding gaps being recalculated. The pace gauge is a narrow arc
// (90 degrees) hugging just the bottom of the circumference, sized and
// positioned so it can't reach up into the text stack above it.
class RunView extends Ui.View {
    // Full-scale deviation (sec per unit) for the pace gauge - beyond this,
    // the marker clamps to the gauge's end. The green "on pace" zone width
    // is driven by Globals.paceBufferSecPerKm, same threshold as the vibrate
    // alert, so the gauge and the buzz always agree with each other.
    const GAUGE_MAX_DEVIATION = 40;

    // Gauge sweeps a 90 degree arc across the bottom of the circle: 225 deg
    // (bottom-left, "too fast") through 270 deg (bottom-center, "on pace") to
    // 315 deg (bottom-right, "too slow"). Standard math-angle convention
    // (0 deg = 3 o'clock, increasing = counter-clockwise). Since this path's
    // angle increases monotonically from 225 to 315, ARC_COUNTER_CLOCKWISE
    // sweeps it the short way through the bottom rather than the long way
    // through the top. NOT visually confirmed in-session (no screen access
    // this session) - if the gauge renders on the wrong side or sweeps
    // through the top, flip this one constant first.
    const GAUGE_START_ANGLE = 225;
    const GAUGE_END_ANGLE = 315;
    const GAUGE_DIRECTION = Gfx.ARC_COUNTER_CLOCKWISE;

    // Same physical-button marker/angle convention as StartConfirmView and
    // NumberEntryView - shown on the target page only, where the button's
    // meaning (back to run page) isn't otherwise obvious.
    const BUTTON_MARKER_CENTER_ANGLE = 30;
    const BUTTON_MARKER_SPAN = 16;

    var _session = null;
    var _timer;
    var _alert;
    var _requiredPace = null;
    var _currentPace = null;
    var _deltaSeconds = null;
    var _elapsedTimeSeconds = 0;
    var _lastInfo = null;
    var _page = 0; // 0 = live run screen, 1 = target summary
    var _paused = false;
    var _finished = false;
    // True only while the stop-confirm menu auto-paused a run that was NOT
    // already paused by the user - lets Back (SaveConfirmMenu.mc) undo
    // exactly that and only that, never a pause the user set deliberately.
    var _autoPausedForMenu = false;

    function initialize() {
        View.initialize();
        _alert = new PaceAlert();
    }

    // Set once Save/Discard has been chosen (SaveConfirmMenu.returnToStartScreen)
    // so the session is never touched again - the unwind back to the start
    // screen pops this view off the stack, which transiently re-reveals it
    // (and fires onShow()) before the final switchToView replaces it. Without
    // this guard, onShow() would call a method on a Session already
    // saved/discarded and crash ("Session that is no longer valid") - hit
    // this for real while testing the v1.6.0 stop-flow change.
    function markFinished() {
        _finished = true;
    }

    function onShow() {
        if (_finished) {
            return;
        }
        if (_session == null) {
            _session = Record.createSession({
                :name => "Pace Target Run",
                :sport => Record.SPORT_RUNNING,
                :subSport => Record.SUB_SPORT_GENERIC
            });
        }
        // _paused guard is required, not optional: onShow() re-fires every
        // time this view is re-revealed by a popped view above it (e.g. the
        // stop-confirm menu's Back item popping back down), not just on the
        // very first show. Without checking _paused here, a paused run that
        // opened the menu via the back button would get silently un-paused
        // the instant the menu closed, regardless of what Back's own handler
        // does or doesn't touch - real bug hit here: pace/time kept
        // advancing after Back even though the menu handler itself was
        // already a no-op. See CHANGELOG.md 2026-08-12.
        if (!_session.isRecording() && !_paused) {
            _session.start();
        }
        // Own the GPS stream for the lifetime of this view. GpsAcquireView
        // warms it up but hands off without disabling it; without this call
        // here too, the ActivityRecording session records with no position
        // stream at all - distance/pace still work off Activity.Info, but no
        // GPS route ends up in the saved FIT file. See CHANGELOG.md
        // 2026-08-12 (v1.7.1).
        Pos.enableLocationEvents(Pos.LOCATION_CONTINUOUS, method(:onPositionInfo));
        _timer = new Timer.Timer();
        _timer.start(method(:onTimerTick), 1000, true);
    }

    function onPositionInfo(info as Pos.Info) as Void {
        // No-op: Activity.getActivityInfo() in onTimerTick() already reads
        // the same underlying stream. This callback only needs to exist so
        // enableLocationEvents has somewhere to deliver to - GPS chip stays
        // on and the session records a route as long as this stays active.
    }

    function onHide() {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        Pos.enableLocationEvents(Pos.LOCATION_DISABLE, method(:onPositionInfo));
    }

    function getSession() {
        return _session;
    }

    function onTimerTick() as Void {
        var info = Activity.getActivityInfo();
        _lastInfo = info;

        var elapsedDistance = info.elapsedDistance;
        var elapsedTimeMs = info.timerTime;
        _elapsedTimeSeconds = elapsedTimeMs != null ? (elapsedTimeMs / 1000) : 0;

        if (elapsedDistance != null) {
            var remainingDistance = Globals.targetDistanceMeters - elapsedDistance;
            var remainingTime = Globals.targetTimeSeconds - _elapsedTimeSeconds;

            _requiredPace = PaceMath.requiredPaceSecPerUnit(remainingDistance, remainingTime);
            _currentPace = PaceMath.currentPaceSecPerUnit(info.currentSpeed);

            if (remainingDistance > 0 && info.currentSpeed != null && info.currentSpeed > 0.0d) {
                var projectedRemainingTime = remainingDistance / info.currentSpeed;
                _deltaSeconds = (remainingTime - projectedRemainingTime).toNumber();
            } else {
                _deltaSeconds = null;
            }

            if (!_paused) {
                _alert.update(_requiredPace, _currentPace, Sys.getTimer());
            }
        } else {
            _requiredPace = null;
            _currentPace = null;
            _deltaSeconds = null;
        }

        Ui.requestUpdate();
    }

    // Short top-button press mid-run: pause/resume toggle, no menu involved -
    // session.stop() freezes elapsedDistance/timerTime so the whole screen
    // naturally holds still (no separate "frozen" bookkeeping needed). Long
    // press (see RunDelegate) opens the stop-summary menu instead.
    function isPaused() {
        return _paused;
    }

    function pauseResume() {
        if (_session == null) {
            return;
        }
        if (_paused) {
            if (!_session.isRecording()) {
                _session.start();
            }
            _paused = false;
        } else {
            if (_session.isRecording()) {
                _session.stop();
            }
            _paused = true;
        }
        Ui.requestUpdate();
    }

    // Called by promptStopConfirm() (SaveConfirmMenu.mc) the instant the
    // stop-confirm menu is about to open, regardless of entry path (long-
    // press or back button, running or already paused). Root cause this
    // fixes: opening the menu previously left the ActivityRecording session
    // running underneath it (session.stop() was only ever called from the
    // Save/Discard branches), so distance/time kept accruing for however
    // long the runner spent deciding - "finished" didn't actually freeze
    // anything until Save/Discard was tapped. Mirrors the existing
    // pause/resume mechanism (session.stop()) rather than inventing a new
    // one. No-ops (and does not set the auto-pause flag) if the run was
    // already paused by the user, so Back can tell the two cases apart.
    function pauseForConfirm() {
        if (_paused) {
            _autoPausedForMenu = false;
            return;
        }
        if (_session != null && _session.isRecording()) {
            _session.stop();
        }
        _paused = true;
        _autoPausedForMenu = true;
        Ui.requestUpdate();
    }

    // Undoes pauseForConfirm() - only if it was the one that paused. Called
    // from SaveConfirmDelegate's :back branch. If the run was already paused
    // by the user before the menu opened, this is a no-op and the run stays
    // paused, same as before this feature existed.
    function resumeFromConfirmBack() {
        if (!_autoPausedForMenu) {
            return;
        }
        _autoPausedForMenu = false;
        if (_session != null && !_session.isRecording()) {
            _session.start();
        }
        _paused = false;
        Ui.requestUpdate();
    }

    // One-line stats string for the stop-confirm menu title (distance, total
    // time, average pace) so stopping shows a summary before Save/Discard/Back.
    function getSummaryText() {
        if (_lastInfo == null || _lastInfo.elapsedDistance == null) {
            return App.loadResource(Rez.Strings.LabelAcquiringGps);
        }
        var unit = PaceMath.formatDistanceUnit();
        var elapsedUnits = _lastInfo.elapsedDistance / PaceMath.unitDistanceMeters();
        var avgPace = PaceMath.requiredPaceSecPerUnit(_lastInfo.elapsedDistance, _elapsedTimeSeconds);
        return elapsedUnits.format("%.2f") + unit + "  " + PaceMath.formatHhMmSs(_elapsedTimeSeconds) + "  " + PaceMath.formatMmSs(avgPace) + "/" + unit;
    }

    // FR7: physical select button press lowers target time; next tick
    // recalculates required pace against the (unchanged) remaining distance.
    function tightenGoal() {
        Globals.targetTimeSeconds -= Globals.adjustStepSeconds;
        if (Globals.targetTimeSeconds < 0) {
            Globals.targetTimeSeconds = 0;
        }
    }

    // Opposite of tightenGoal() - raises target time back up (loosen).
    function looseGoal() {
        Globals.targetTimeSeconds += Globals.adjustStepSeconds;
    }

    // Tap-zone dispatch for the target page: top half of the screen loosens,
    // bottom half tightens. Screen height comes from device settings (not
    // dc), since this is called from the delegate, outside onUpdate().
    function handleTargetTap(y) {
        var h = Sys.getDeviceSettings().screenHeight;
        if (y < h / 2) {
            looseGoal();
        } else {
            tightenGoal();
        }
        Ui.requestUpdate();
    }

    function togglePage() {
        _page = 1 - _page;
        Ui.requestUpdate();
    }

    function getPage() {
        return _page;
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        if (_page == 1) {
            drawTargetPage(dc, cx, w, h);
            return;
        }

        if (_lastInfo == null || _lastInfo.elapsedDistance == null) {
            dc.drawText(cx, cy, Gfx.FONT_MEDIUM, App.loadResource(Rez.Strings.LabelAcquiringGps), Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var unit = PaceMath.formatDistanceUnit();
        var sectionGap = h * 0.01;

        var y = h * 0.15;
        if (_paused) {
            dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_BLACK);
            dc.drawText(cx, y, Gfx.FONT_XTINY, "PAUSED", Gfx.TEXT_JUSTIFY_CENTER);
            y += dc.getFontHeight(Gfx.FONT_XTINY);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        } else {
            // Current pace sits next to Total Time (not stacked below it,
            // where Required Pace/Distance already are) so the runner can
            // read "how fast am I going right now" without waiting for the
            // gauge to settle - added 2026-08-24, was missing entirely
            // before. FONT_SMALL (down from Total Time's old FONT_MEDIUM)
            // so both columns fit side by side without crowding.
            y = drawLabeledValuePair(dc, y, w * 0.30, w * 0.70,
                "Total Time", PaceMath.formatHhMmSs(_elapsedTimeSeconds),
                App.loadResource(Rez.Strings.LabelCurrentPace), PaceMath.formatMmSs(_currentPace) + "/" + unit,
                Gfx.FONT_SMALL);
        }
        y += sectionGap;
        y += sectionGap;
        y = drawLabeledValue(dc, cx, y, App.loadResource(Rez.Strings.LabelRequiredPace), PaceMath.formatMmSs(_requiredPace) + "/" + unit, Gfx.FONT_NUMBER_MEDIUM);
        // y += sectionGap;
        var elapsedUnits = _lastInfo.elapsedDistance / PaceMath.unitDistanceMeters();
        y = drawLabeledValue(dc, cx, y, App.loadResource(Rez.Strings.LabelDistance), elapsedUnits.format("%.2f") + " " + unit, Gfx.FONT_SMALL);
        y += sectionGap;

        // var deltaText = _deltaSeconds == null ? "--:--" : ((_deltaSeconds >= 0 ? "+" : "-") + PaceMath.formatMmSs(_deltaSeconds));
        // dc.drawText(cx, y, Gfx.FONT_XTINY, App.loadResource(Rez.Strings.LabelDelta) + " " + deltaText, Gfx.TEXT_JUSTIFY_CENTER);

        var minDim = w < h ? w : h;
        drawPaceGauge(dc, cx, cy, minDim / 2 * 0.90, minDim * 0.035);
    }

    // Second page (swipe up/down, or a device's next/prev-page buttons, to
    // reach it): shows the target as currently adjusted by tighten/loosen,
    // since the main page only ever shows *required* pace against remaining
    // distance/time, never the standing target itself. Target is adjusted by
    // tapping the top half of the screen (loosen) or bottom half (tighten) -
    // see RunDelegate.onTap / RunView.handleTargetTap. Swipe-to-adjust
    // (2026-08-04) was replaced with this: it was never confirmed to reach
    // the device on real hardware, while tap is the one input proven, if
    // anything, too reliable at firing - and the accidental-trigger risk
    // that got tap banned elsewhere doesn't apply to a page reached only by
    // a deliberate navigation swipe.
    function drawTargetPage(dc, cx, w, h) {
        var unit = PaceMath.formatDistanceUnit();
        var targetUnits = Globals.targetDistanceMeters / PaceMath.unitDistanceMeters();
        var targetPace = PaceMath.requiredPaceSecPerUnit(Globals.targetDistanceMeters, Globals.targetTimeSeconds);
        var sectionGap = h * 0.02;

        dc.drawText(cx, h * 0.06, Gfx.FONT_SMALL, "+", Gfx.TEXT_JUSTIFY_CENTER);

        var y = h * 0.20;
        y = drawLabeledValue(dc, cx, y, "Target Distance", targetUnits.format("%.2f") + " " + unit, Gfx.FONT_XTINY);
        y += sectionGap;
        y = drawLabeledValue(dc, cx, y, "Target Time", PaceMath.formatHhMmSs(Globals.targetTimeSeconds), Gfx.FONT_NUMBER_MEDIUM);
        // y += sectionGap;
        y = drawLabeledValue(dc, cx, y, "Target Pace", PaceMath.formatMmSs(targetPace) + "/" + unit, Gfx.FONT_SMALL);

        dc.drawText(cx, h * 0.90, Gfx.FONT_SMALL, "-", Gfx.TEXT_JUSTIFY_CENTER);

        var minDim = w < h ? w : h;
        drawButtonMarker(dc, cx, h / 2, minDim / 2 * 0.97, minDim * 0.02);
    }

    // Thin arc hugging the bezel near the physical button - same visual
    // language as StartConfirmView/NumberEntryView. Here it means "button
    // returns to the run page" rather than confirm.
    function drawButtonMarker(dc, cx, cy, radius, thickness) {
        dc.setPenWidth(thickness);
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_BLACK);
        dc.drawArc(cx, cy, radius, Gfx.ARC_COUNTER_CLOCKWISE,
            BUTTON_MARKER_CENTER_ANGLE - BUTTON_MARKER_SPAN / 2,
            BUTTON_MARKER_CENTER_ANGLE + BUTTON_MARKER_SPAN / 2);
        dc.setPenWidth(1);
    }

    // Draws a caption (FONT_XTINY) above a value in valueFont, stacked with
    // no gap between them, and returns the Y just below the value - so
    // callers can chain sections without ever guessing at overlap.
    function drawLabeledValue(dc, cx, yTop, label, value, valueFont) {
        var capFont = Gfx.FONT_XTINY;
        dc.drawText(cx, yTop, capFont, label, Gfx.TEXT_JUSTIFY_CENTER);
        var yValue = yTop + dc.getFontHeight(capFont) -4;
        dc.drawText(cx, yValue, valueFont, value, Gfx.TEXT_JUSTIFY_CENTER);
        return yValue + dc.getFontHeight(valueFont);
    }

    // Two drawLabeledValue() columns side by side at the same yTop (e.g.
    // Total Time / Current Pace), instead of stacked - returns the taller
    // column's bottom edge so the caller can keep chaining without overlap,
    // same contract as drawLabeledValue().
    function drawLabeledValuePair(dc, yTop, leftCx, rightCx, label1, value1, label2, value2, valueFont) {
        var yBottom1 = drawLabeledValue(dc, leftCx, yTop, label1, value1, valueFont);
        var yBottom2 = drawLabeledValue(dc, rightCx, yTop, label2, value2, valueFont);
        return yBottom1 > yBottom2 ? yBottom1 : yBottom2;
    }

    function drawTextValue(dc, cx, yTop, label, value, valueFont) {
        var capFont = Gfx.FONT_XTINY;
        dc.drawText(cx, yTop, capFont, label, Gfx.TEXT_JUSTIFY_CENTER);
        var yValue = yTop + dc.getFontHeight(capFont);
        dc.drawText(cx, yValue, valueFont, value, Gfx.TEXT_JUSTIFY_CENTER);
        return yValue + dc.getFontHeight(valueFont);
    }

    // Barometer-style gauge arc hugging the bottom of the circumference:
    // blue (too fast) - green (on pace) - red (too slow), left to right,
    // with a marker dot at the current pace-vs-required deviation. Blue/red
    // match the fast/slow PaceAlert vibe directions (two short buzzes vs.
    // one long buzz) so the gauge's two ends are distinguishable at a
    // glance, not just by position. Green span tracks
    // Globals.paceBufferSecPerKm so this always visually agrees with when
    // the vibrate alert would trigger.
    function drawPaceGauge(dc, cx, cy, radius, thickness) {
        var totalSpan = GAUGE_END_ANGLE - GAUGE_START_ANGLE;

        var greenFrac = Globals.paceBufferSecPerKm.toDouble() / GAUGE_MAX_DEVIATION;
        if (greenFrac > 1.0) {
            greenFrac = 1.0;
        }
        var greenSpan = totalSpan * greenFrac;
        var greenStart = GAUGE_START_ANGLE + (totalSpan - greenSpan) / 2;
        var greenEnd = greenStart + greenSpan;

        dc.setPenWidth(thickness);

        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_BLACK);
        dc.drawArc(cx, cy, radius, GAUGE_DIRECTION, GAUGE_START_ANGLE, greenStart);

        dc.setColor(Gfx.COLOR_DK_RED, Gfx.COLOR_BLACK);
        dc.drawArc(cx, cy, radius, GAUGE_DIRECTION, greenEnd, GAUGE_END_ANGLE);

        dc.setColor(Gfx.COLOR_DK_GREEN, Gfx.COLOR_BLACK);
        dc.drawArc(cx, cy, radius, GAUGE_DIRECTION, greenStart, greenEnd);

        dc.setPenWidth(1);

        if (_requiredPace == null || _currentPace == null) {
            return;
        }

        var deviation = _currentPace - _requiredPace;
        if (deviation > GAUGE_MAX_DEVIATION) {
            deviation = GAUGE_MAX_DEVIATION;
        } else if (deviation < -GAUGE_MAX_DEVIATION) {
            deviation = -GAUGE_MAX_DEVIATION;
        }
        var frac = deviation.toDouble() / GAUGE_MAX_DEVIATION;
        var markerAngleDeg = 270 + (frac * (totalSpan / 2));
        var markerAngleRad = Math.toRadians(markerAngleDeg);
        var markerX = cx + (radius * Math.cos(markerAngleRad));
        var markerY = cy - (radius * Math.sin(markerAngleRad));

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.fillCircle(markerX, markerY, thickness * 0.7);
    }
}
