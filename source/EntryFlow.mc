using Toybox.WatchUi as Ui;

// FR1/FR2: sequential custom-distance -> hours -> minutes -> seconds flow,
// each a NumberEntryView/Delegate pair. Back button naturally pops to the
// previous step (BehaviorDelegate default), no custom back handling needed.

function pushCustomDistanceEntry() {
    var v = new NumberEntryView("Distance", 1, 200, 5, 0, PaceMath.formatDistanceUnit());
    Globals.entryStackDepth += 1;
    Ui.pushView(v, new DistanceEntryDelegate(v), Ui.SLIDE_LEFT);
}

function pushHourEntry() {
    var v = new NumberEntryView("Hours", 0, 5, 0, 0, "h");
    Globals.entryStackDepth += 1;
    Ui.pushView(v, new HourEntryDelegate(v), Ui.SLIDE_LEFT);
}

function pushMinuteEntry() {
    var v = new NumberEntryView("Minutes", 0, 59, 25, 2, "m");
    Globals.entryStackDepth += 1;
    Ui.pushView(v, new MinuteEntryDelegate(v), Ui.SLIDE_LEFT);
}

function pushSecondEntry() {
    var v = new NumberEntryView("Seconds", 0, 59, 0, 2, "s");
    Globals.entryStackDepth += 1;
    Ui.pushView(v, new SecondEntryDelegate(v), Ui.SLIDE_LEFT);
}

class DistanceEntryDelegate extends NumberEntryDelegate {
    function initialize(view) {
        NumberEntryDelegate.initialize(view);
    }

    function confirm() {
        Globals.targetDistanceMeters = _view.getValue().toDouble() * PaceMath.unitDistanceMeters();
        pushHourEntry();
    }
}

class HourEntryDelegate extends NumberEntryDelegate {
    function initialize(view) {
        NumberEntryDelegate.initialize(view);
    }

    function confirm() {
        Globals.tmpHours = _view.getValue();
        pushMinuteEntry();
    }
}

class MinuteEntryDelegate extends NumberEntryDelegate {
    function initialize(view) {
        NumberEntryDelegate.initialize(view);
    }

    function confirm() {
        Globals.tmpMinutes = _view.getValue();
        pushSecondEntry();
    }
}

class SecondEntryDelegate extends NumberEntryDelegate {
    function initialize(view) {
        NumberEntryDelegate.initialize(view);
    }

    function confirm() {
        Globals.targetTimeSeconds = (Globals.tmpHours * 3600) + (Globals.tmpMinutes * 60) + _view.getValue();
        var gpsView = new GpsAcquireView();
        Ui.switchToView(gpsView, new GpsAcquireDelegate(gpsView), Ui.SLIDE_LEFT);
    }
}
