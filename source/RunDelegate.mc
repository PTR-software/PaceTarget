using Toybox.WatchUi as Ui;
using Toybox.System as Sys;

class RunDelegate extends Ui.BehaviorDelegate {
    // Short top-button press = pause/resume, long press = stop (opens the
    // summary/save menu). Measured via onKeyPressed/onKeyReleased (the
    // granular press+release pair, distinct from onKey which only fires
    // once already-combined) since onKey alone carries no duration. This is
    // a new callback pair for this codebase - onKey(KEY_ENTER) is the only
    // physical-button path empirically confirmed so far (CHANGELOG
    // 2026-07-28 round 3) - so debug logging is kept in per that same
    // verify-before-trusting convention until confirmed on hardware/sim.
    const HOLD_THRESHOLD_MS = 600;

    var _view;
    var _keyDownMs = null;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
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

    // On the target page, tap is repurposed as the adjust control: top half
    // of the screen loosens, bottom half tightens (see RunView.handleTargetTap).
    // This is deliberate reuse of tap - previously banned on the run page for
    // accidental-trigger risk (sweat/sleeve/arm-swing mid-run) - because the
    // target page is a screen the user navigates to on purpose; there's no
    // "accidental tap while just running" risk here the way there is on the
    // live page. Swapped in after swipe-to-adjust (2026-08-04) was never
    // confirmed to actually reach the device on real hardware - tap is the
    // one input BehaviorDelegate has proven, if anything, too reliable at
    // firing (see onSelect/onTap fusion, CHANGELOG 2026-07-28 round 3).
    function onTap(evt) {
        if (_view.getPage() == 1) {
            var coords = evt.getCoordinates();
            _view.handleTargetTap(coords[1]);
            return true;
        }
        return true;
    }

    // Swipe now only navigates between the run page and target page, in
    // either direction - target-value adjustment moved to tap zones above.
    function onSwipe(swipeEvent) {
        var dir = swipeEvent.getDirection();
        if (dir != Ui.SWIPE_UP && dir != Ui.SWIPE_DOWN) {
            return false;
        }
        _view.togglePage();
        return true;
    }

    function onNextPage() {
        _view.togglePage();
        return true;
    }

    function onPreviousPage() {
        _view.togglePage();
        return true;
    }

    // Physical top button on the target page (page 1): returns to the run
    // page. On the run page (page 0), KEY_ENTER is swallowed here (return
    // true, no side effect) because the actual pause-vs-stop decision needs
    // press duration, handled below in onKeyPressed/onKeyReleased instead -
    // tighten moved off this button entirely, onto the target-page tap zones
    // (RunView.handleTargetTap).
    function onKey(keyEvent) {
        if (keyEvent.getKey() == Ui.KEY_ENTER) {
            if (_view.getPage() == 1) {
                _view.togglePage();
            }
            return true;
        }
        return false;
    }

    // Records press time; the pause-vs-stop decision happens on release,
    // once the hold duration is known.
    function onKeyPressed(keyEvent) {
        if (keyEvent.getKey() == Ui.KEY_ENTER && _view.getPage() == 0) {
            _keyDownMs = Sys.getTimer();
            return true;
        }
        return false;
    }

    // Short press -> pause/resume toggle. Long press (>= HOLD_THRESHOLD_MS)
    // -> open the stop-summary menu (Save/Discard/Back).
    function onKeyReleased(keyEvent) {
        if (keyEvent.getKey() == Ui.KEY_ENTER && _view.getPage() == 0 && _keyDownMs != null) {
            var heldMs = Sys.getTimer() - _keyDownMs;
            _keyDownMs = null;
            if (heldMs >= HOLD_THRESHOLD_MS) {
                promptStopConfirm(_view);
            } else {
                _view.pauseResume();
            }
            return true;
        }
        return false;
    }

    // FR9: back button opens the stop/save confirmation from the run page;
    // from the target page it just returns to the run page instead.
    function onBack() {
        if (_view.getPage() == 1) {
            _view.togglePage();
            return true;
        }
        promptStopConfirm(_view);
        return true;
    }
}
