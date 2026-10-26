using Toybox.WatchUi as Ui;
using Toybox.Application as App;

// FR1: setup screen distance presets + custom entry.
class DistanceMenuView extends Ui.Menu2 {
    function initialize() {
        Globals.entryStackDepth = 0;
        Menu2.initialize({ :title => "Pace Target v" + Globals.APP_VERSION });
        addItem(new Ui.MenuItem(App.loadResource(Rez.Strings.MenuDistance5k), null, :d5k, {}));
        addItem(new Ui.MenuItem(App.loadResource(Rez.Strings.MenuDistance10k), null, :d10k, {}));
        addItem(new Ui.MenuItem(App.loadResource(Rez.Strings.MenuDistanceHalf), null, :dhalf, {}));
        addItem(new Ui.MenuItem(App.loadResource(Rez.Strings.MenuDistanceMarathon), null, :dmarathon, {}));
        addItem(new Ui.MenuItem(App.loadResource(Rez.Strings.MenuDistanceCustom), null, :dcustom, {}));
    }
}

class DistanceMenuDelegate extends Ui.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :d5k) {
            Globals.targetDistanceMeters = 5000.0d;
            pushHourEntry();
        } else if (id == :d10k) {
            Globals.targetDistanceMeters = 10000.0d;
            pushHourEntry();
        } else if (id == :dhalf) {
            Globals.targetDistanceMeters = 21097.5d;
            pushHourEntry();
        } else if (id == :dmarathon) {
            Globals.targetDistanceMeters = 42195.0d;
            pushHourEntry();
        } else if (id == :dcustom) {
            pushCustomDistanceEntry();
        }
    }
}
