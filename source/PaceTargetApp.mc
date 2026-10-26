using Toybox.Application as App;
using Toybox.WatchUi as Ui;

class PaceTargetApp extends App.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new DistanceMenuView(), new DistanceMenuDelegate() ];
    }
}
