using Toybox.WatchUi as Ui;
using Toybox.Application as App;

// FR9: standard stop-and-save flow so the activity ends up as a normal
// Garmin Connect run (or is discarded / recording resumed). Title shows a
// stats summary (distance/time/avg pace) ahead of the Save/Discard/Back
// choice, since a long-press-to-stop should let the runner see what they're
// about to save before committing.
function promptStopConfirm(runView) {
    // Freeze the session the instant "finish" is invoked (long-press or
    // back), not only once Save/Discard is actually tapped - otherwise
    // distance/time keep accruing underneath the menu for however long the
    // runner spends deciding. See RunView.pauseForConfirm(). Must happen
    // before getSummaryText() so the summary shown matches the frozen state.
    runView.pauseForConfirm();
    var title = runView.getSummaryText() + "  " + App.loadResource(Rez.Strings.LabelConfirmSave);
    var menu = new Ui.Menu2({ :title => title });
    menu.addItem(new Ui.MenuItem(App.loadResource(Rez.Strings.LabelSave), null, :save, {}));
    menu.addItem(new Ui.MenuItem(App.loadResource(Rez.Strings.LabelDiscard), null, :discard, {}));
    menu.addItem(new Ui.MenuItem(App.loadResource(Rez.Strings.LabelBack), null, :back, {}));
    Ui.pushView(menu, new SaveConfirmDelegate(runView), Ui.SLIDE_UP);
}

// Save/Discard both end the run and go back to setup, rather than closing
// the app outright (the previous Sys.exit() behavior).
//
// WatchUi.switchToView() only pops ONE view and pushes the new one - it does
// NOT clear the whole stack (confirmed against the SDK docs after this first
// implementation crashed: "Pop the current View from the View stack and push
// a new one"). The actual stack at this point is
// [DistanceMenuView, Hour, Minute, (Custom?), RunView, thisMenu] - Hour/
// Minute/Second are real pushes, StartConfirmView/RunView instead each
// replaced the layer below via switchToView (net depth unchanged), so
// Globals.entryStackDepth (incremented per push in EntryFlow.mc) plus one
// more for this stop-confirm menu itself is exactly the number of pops
// needed to get back down to the original root DistanceMenuView, which is
// then swapped for a fresh one (so leftover entry-flow state doesn't linger
// as a stale screen reachable by mashing back).
function returnToStartScreen(runView) {
    runView.markFinished();
    var pops = Globals.entryStackDepth + 1;
    var i = 0;
    while (i < pops) {
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        i += 1;
    }
    Ui.switchToView(new DistanceMenuView(), new DistanceMenuDelegate(), Ui.SLIDE_IMMEDIATE);
}

class SaveConfirmDelegate extends Ui.Menu2InputDelegate {
    var _view;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item) {
        var id = item.getId();
        var session = _view.getSession();

        if (id == :save) {
            if (session != null) {
                if (session.isRecording()) {
                    session.stop();
                }
                session.save();
            }
            // markFinished() here too (not just inside returnToStartScreen,
            // called ~2s later from SavingView) so the already-saved session
            // is never touched again even in that window - defensive, same
            // guard RunView.onShow() already relies on elsewhere.
            _view.markFinished();
            Ui.switchToView(new SavingView(_view), new SavingDelegate(), Ui.SLIDE_IMMEDIATE);
        } else if (id == :discard) {
            if (session != null) {
                if (session.isRecording()) {
                    session.stop();
                }
                session.discard();
            }
            returnToStartScreen(_view);
        } else if (id == :back) {
            // As of 2026-08-24, opening this menu DOES freeze the session
            // (promptStopConfirm() -> pauseForConfirm()), so Back has to
            // undo exactly that - resumeFromConfirmBack() is a no-op if the
            // run was already paused by the user before the menu opened, so
            // that case still returns to paused, same as the historical
            // behavior described below. Renamed from "Resume" (which
            // implied this always un-pauses) after a real bug where this
            // branch force-started the session unconditionally, leaving a
            // paused run silently resumed with a stuck PAUSED label -
            // see CHANGELOG.md 2026-08-12.
            _view.resumeFromConfirmBack();
            Ui.popView(Ui.SLIDE_DOWN);
        }
    }
}
