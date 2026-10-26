using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application as App;
using Toybox.Position as Pos;
using Toybox.System as Sys;

// Inserted between the entry flow (seconds confirm) and StartConfirmView.
// Field report 2026-08-12: recording used to start the instant StartConfirmView
// was confirmed, but a real GPS fix took far longer to resolve than the
// on-screen "Acquiring GPS..." message on RunView implied - one real run got
// ~500m in before a usable fix landed, so required pace was computed off
// bad/absent distance data for that whole stretch. This screen holds here,
// off the recording session entirely, until Position reports a fix of at
// least READY_QUALITY - so by the time the runner reaches "Ready" and starts
// RunView's session, GPS is already warm and the first distance sample is
// trustworthy.
class GpsAcquireView extends Ui.View {
    // QUALITY_GOOD is the SDK's best tier but can take a long time outdoors
    // and may never be reached under tree cover/urban canyon; QUALITY_USABLE
    // is the SDK's own "good enough to use" tier - chosen as the minimum bar.
    const READY_QUALITY = Pos.QUALITY_USABLE;

    const BUTTON_MARKER_CENTER_ANGLE = 30;
    const BUTTON_MARKER_SPAN = 16;

    var _acquiring = false;
    var _quality = Pos.QUALITY_NOT_AVAILABLE;

    function initialize() {
        View.initialize();
    }

    function onHide() {
        if (_acquiring) {
            Pos.enableLocationEvents(Pos.LOCATION_DISABLE, method(:onPositionInfo));
        }
    }

    function isAcquiring() {
        return _acquiring;
    }

    function startAcquiring() {
        _acquiring = true;
        Pos.enableLocationEvents(Pos.LOCATION_CONTINUOUS, method(:onPositionInfo));
        Ui.requestUpdate();
    }

    // Second button press while acquiring skips the wait and proceeds anyway
    // - deliberate escape hatch so a fix that never resolves (indoors, deep
    // urban canyon, or the simulator with no GPX playback started yet) can't
    // strand the runner on this screen with no way forward except backing
    // all the way out of the entry flow.
    function skipWait() {
        proceed();
    }

    function onPositionInfo(info as Pos.Info) as Void {
        if (info != null && info.accuracy != null) {
            _quality = info.accuracy;
        }
        if (_acquiring && _quality >= READY_QUALITY) {
            proceed();
            return;
        }
        Ui.requestUpdate();
    }

    function proceed() {
        // Deliberately do NOT disable location events here: ownership of the
        // GPS stream hands off to RunView, which re-registers its own
        // callback in onShow(). Disabling here (as this used to do) turned
        // the GPS chip off right as recording started, so the FIT session
        // never got a position stream at all - no route data, even though
        // distance/pace kept working off other Activity.Info fields. See
        // CHANGELOG.md 2026-08-12 (v1.7.1).
        _acquiring = false;
        Ui.switchToView(new StartConfirmView(), new StartConfirmDelegate(), Ui.SLIDE_LEFT);
    }

    function qualityLabel() {
        if (_quality == Pos.QUALITY_GOOD) {
            return "Good";
        } else if (_quality == Pos.QUALITY_USABLE) {
            return "Usable";
        } else if (_quality == Pos.QUALITY_POOR) {
            return "Poor";
        } else if (_quality == Pos.QUALITY_LAST_KNOWN) {
            return "Last known";
        }
        return "Searching";
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        if (!_acquiring) {
            dc.drawText(cx, h * 0.30, Gfx.FONT_SMALL, App.loadResource(Rez.Strings.LabelActivateGpsTitle), Gfx.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(cx, h * 0.30, Gfx.FONT_SMALL, App.loadResource(Rez.Strings.LabelAcquiringGps), Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, h * 0.46, Gfx.FONT_MEDIUM, qualityLabel(), Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        }

        var minDim = w < h ? w : h;
        drawButtonMarker(dc, cx, cy, minDim / 2 * 0.97, minDim * 0.02);
    }

    // Same bezel-hugging arc as StartConfirmView/NumberEntryView.
    function drawButtonMarker(dc, cx, cy, radius, thickness) {
        dc.setPenWidth(thickness);
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_BLACK);
        dc.drawArc(cx, cy, radius, Gfx.ARC_COUNTER_CLOCKWISE,
            BUTTON_MARKER_CENTER_ANGLE - BUTTON_MARKER_SPAN / 2,
            BUTTON_MARKER_CENTER_ANGLE + BUTTON_MARKER_SPAN / 2);
        dc.setPenWidth(1);
    }
}

class GpsAcquireDelegate extends Ui.BehaviorDelegate {
    var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Same physical-button-only convention as the rest of the app -
    // onSelect()/onTap() fire identically for touch and physical press, so
    // both are no-ops here; onKey(KEY_ENTER) is the only real hook.
    function onSelect() {
        return false;
    }

    function onTap(evt) {
        return true;
    }

    function onKey(keyEvent) {
        if (keyEvent.getKey() == Ui.KEY_ENTER) {
            if (_view.isAcquiring()) {
                _view.skipWait();
            } else {
                _view.startAcquiring();
            }
            return true;
        }
        return false;
    }
}
