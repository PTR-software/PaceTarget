using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Timer as Timer;

// Shown for ~2s right after Save is chosen, before returning to the start
// screen - confirms to the runner that the activity actually got saved
// before the screen changes out from under them. No built-in "saving"
// spinner/checkmark widget exists in this SDK (checked api.debug.xml - only
// WatchUi.showToast, a plain text toast, no animation) - same "doesn't
// exist, build our own" situation as NumberEntryView replacing
// WatchUi.Picker, so this is a small self-drawn spinning arc instead.
class SavingView extends Ui.View {
    const DURATION_MS = 2000;
    // 30ms was rejected by the device/sim's minimum timer interval at
    // runtime ("Timer interval is too small... set to the minimum supported
    // value" - caught live via the auto-drive harness's debug log). 50ms is
    // still smooth for a spinner and stays clear of that clamp.
    const TICK_MS = 50;
    const SPIN_SPAN_DEG = 270;
    const SPIN_SPEED_DEG_PER_TICK = 12;

    var _runView;
    var _timer;
    var _elapsedMs = 0;
    var _angle = 0;

    function initialize(runView) {
        View.initialize();
        _runView = runView;
    }

    function onShow() {
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), TICK_MS, true);
    }

    function onHide() {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        _elapsedMs += TICK_MS;
        _angle = (_angle + SPIN_SPEED_DEG_PER_TICK) % 360;

        if (_elapsedMs >= DURATION_MS) {
            if (_timer != null) {
                _timer.stop();
                _timer = null;
            }
            returnToStartScreen(_runView);
            return;
        }

        Ui.requestUpdate();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var radius = (w < h ? w : h) * 0.28;

        dc.setPenWidth(w * 0.035);
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_BLACK);
        dc.drawArc(cx, cy, radius, Gfx.ARC_CLOCKWISE, _angle, _angle + SPIN_SPAN_DEG);
        dc.setPenWidth(1);

        dc.drawText(cx, cy + radius + dc.getFontHeight(Gfx.FONT_SMALL), Gfx.FONT_SMALL, "Saved", Gfx.TEXT_JUSTIFY_CENTER);
    }
}

// Swallows all input while the save animation plays - this screen is
// non-interactive by design, same "deliberate, controlled transition"
// convention as the rest of the app's confirm screens.
class SavingDelegate extends Ui.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onKey(keyEvent) {
        return true;
    }

    function onSelect() {
        return true;
    }

    function onTap(evt) {
        return true;
    }

    function onBack() {
        return true;
    }
}
