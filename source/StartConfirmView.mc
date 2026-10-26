using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Application as App;

// Summary screen shown after distance/time entry, before recording starts.
// Recording used to begin the instant the entry flow finished (RunView.onShow
// starts the session unconditionally) - too soon, since the runner hasn't
// necessarily started moving yet. This screen holds on the setup summary
// until an explicit physical-button press, matching the same button-only
// confirm convention as NumberEntryView/RunDelegate (onSelect/onTap are
// no-ops on touch devices; onKey(KEY_ENTER) is the only real confirm).
class StartConfirmView extends Ui.View {
    // Angle convention matches RunView's gauge: 0 deg = 3 o'clock, increasing
    // counter-clockwise (so clock-hour H maps to (3-H)*30 deg). User directly
    // confirmed 60 deg rendered at 1 o'clock - validates that mapping - and
    // asked for 2 o'clock instead, i.e. 30 deg.
    const BUTTON_MARKER_CENTER_ANGLE = 30;
    const BUTTON_MARKER_SPAN = 16;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        var unit = PaceMath.formatDistanceUnit();
        var distUnits = Globals.targetDistanceMeters / PaceMath.unitDistanceMeters();

        dc.drawText(cx, h * 0.20, Gfx.FONT_SMALL, App.loadResource(Rez.Strings.LabelReadyTitle), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.46, Gfx.FONT_NUMBER_MEDIUM, distUnits.format("%.2f") + " " + unit, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, h * 0.62, Gfx.FONT_MEDIUM, PaceMath.formatHhMmSs(Globals.targetTimeSeconds), Gfx.TEXT_JUSTIFY_CENTER);

        var minDim = w < h ? w : h;
        drawButtonMarker(dc, cx, cy, minDim / 2 * 0.97, minDim * 0.02);
    }

    // Thin, short rounded-looking arc hugging the bezel near the physical
    // button, replacing the old "button = Start" text hint.
    function drawButtonMarker(dc, cx, cy, radius, thickness) {
        dc.setPenWidth(thickness);
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_BLACK);
        dc.drawArc(cx, cy, radius, Gfx.ARC_COUNTER_CLOCKWISE,
            BUTTON_MARKER_CENTER_ANGLE - BUTTON_MARKER_SPAN / 2,
            BUTTON_MARKER_CENTER_ANGLE + BUTTON_MARKER_SPAN / 2);
        dc.setPenWidth(1);
    }
}

class StartConfirmDelegate extends Ui.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    // Same rationale as RunDelegate/NumberEntryDelegate: onSelect() fires for
    // both physical button and plain tap on touch devices, indistinguishable
    // once fired, so it's a no-op here and onKey(KEY_ENTER) is the real hook.
    function onSelect() {
        return false;
    }

    function onTap(evt) {
        return true;
    }

    function onKey(keyEvent) {
        if (keyEvent.getKey() == Ui.KEY_ENTER) {
            var runView = new RunView();
            Ui.switchToView(runView, new RunDelegate(runView), Ui.SLIDE_LEFT);
            return true;
        }
        return false;
    }
}
