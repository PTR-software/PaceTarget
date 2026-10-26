using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;

// FR1/FR2: fully custom number entry (distance / hours / minutes / seconds).
// Replaces Toybox.WatchUi.Picker - that widget's layout/touch behavior isn't
// documented precisely enough to control reliably (title requirements,
// multi-column positioning, confirm hit zones), so this draws everything
// itself: swipe up/down to adjust, physical select button to confirm (tap-to-
// confirm was removed - too easy to fat-finger mid-adjustment), back button
// uses BehaviorDelegate's default pop behavior.
class NumberEntryView extends Ui.View {
    // Same physical-button marker/angle convention as StartConfirmView.
    const BUTTON_MARKER_CENTER_ANGLE = 30;
    const BUTTON_MARKER_SPAN = 16;

    var _label;
    var _min;
    var _max;
    var _value;
    var _pad;
    var _suffix;

    function initialize(label, min, max, initial, pad, suffix) {
        View.initialize();
        _label = label;
        _min = min;
        _max = max;
        _value = initial;
        _pad = pad;
        _suffix = suffix;
    }

    function increase() {
        _value += 1;
        if (_value > _max) {
            _value = _min;
        }
        Ui.requestUpdate();
    }

    function decrease() {
        _value -= 1;
        if (_value < _min) {
            _value = _max;
        }
        Ui.requestUpdate();
    }

    function getValue() {
        return _value;
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.drawText(w / 2, h * 0.16, Gfx.FONT_SMALL, _label, Gfx.TEXT_JUSTIFY_CENTER);

        var numText = _pad > 0 ? _value.format("%0" + _pad.format("%d") + "d") : _value.format("%d");
        dc.drawText(w / 2, h / 2, Gfx.FONT_NUMBER_MEDIUM, numText + _suffix, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        dc.drawText(w / 2, h * 0.82, Gfx.FONT_XTINY, "^ swipe v", Gfx.TEXT_JUSTIFY_CENTER);

        var minDim = w < h ? w : h;
        drawButtonMarker(dc, w / 2, h / 2, minDim / 2 * 0.97, minDim * 0.02);
    }

    // Thin arc hugging the bezel near the physical button - same visual
    // language as StartConfirmView's, replacing the old "button = OK" text.
    function drawButtonMarker(dc, cx, cy, radius, thickness) {
        dc.setPenWidth(thickness);
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_BLACK);
        dc.drawArc(cx, cy, radius, Gfx.ARC_COUNTER_CLOCKWISE,
            BUTTON_MARKER_CENTER_ANGLE - BUTTON_MARKER_SPAN / 2,
            BUTTON_MARKER_CENTER_ANGLE + BUTTON_MARKER_SPAN / 2);
        dc.setPenWidth(1);
    }
}

// Shared nav logic; subclasses override confirm() for their specific next step.
class NumberEntryDelegate extends Ui.BehaviorDelegate {
    var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() {
        _view.decrease();
        return true;
    }

    function onPreviousPage() {
        _view.increase();
        return true;
    }

    function onSwipe(swipeEvent) {
        var dir = swipeEvent.getDirection();
        if (dir == Ui.SWIPE_UP) {
            _view.increase();
            return true;
        }
        if (dir == Ui.SWIPE_DOWN) {
            _view.decrease();
            return true;
        }
        return false;
    }

    // On Venu 3 (and touch devices generally), BehaviorDelegate synthesizes
    // onSelect() from BOTH a physical button press and a plain screen tap -
    // confirmed empirically via debug logging, they are indistinguishable
    // once onSelect() fires. onSelect() is therefore left as a no-op here;
    // the real physical-button-only hook is onKey(), which the SDK docs
    // describe explicitly as "a physical button has been pressed and
    // released" - genuinely distinct from touch, unlike onSelect/onTap.
    function onSelect() {
        return false;
    }

    function onTap(evt) {
        return true;
    }

    function onKey(keyEvent) {
        if (keyEvent.getKey() == Ui.KEY_ENTER) {
            confirm();
            return true;
        }
        return false;
    }

    function confirm() {
    }
}
