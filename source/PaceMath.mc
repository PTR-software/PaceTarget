using Toybox.System as Sys;

module PaceMath {

    const METERS_PER_KM = 1000.0d;
    const METERS_PER_MILE = 1609.344d;

    function isMetric() {
        return Sys.getDeviceSettings().distanceUnits == Sys.UNIT_METRIC;
    }

    function unitDistanceMeters() {
        return isMetric() ? METERS_PER_KM : METERS_PER_MILE;
    }

    // Seconds per unit-distance (per km or per mile) required to cover the
    // remaining distance in the remaining time. Null when not computable
    // (e.g. no GPS distance yet) so callers can render a placeholder.
    function requiredPaceSecPerUnit(remainingDistanceMeters, remainingTimeSeconds) {
        if (remainingDistanceMeters == null || remainingDistanceMeters <= 0.0d) {
            return null;
        }
        if (remainingTimeSeconds <= 0) {
            return 0;
        }
        var secPerMeter = remainingTimeSeconds.toDouble() / remainingDistanceMeters;
        return (secPerMeter * unitDistanceMeters()).toNumber();
    }

    // currentSpeedMps is Activity.Info.currentSpeed (meters/second, possibly null pre-GPS-fix).
    function currentPaceSecPerUnit(currentSpeedMps) {
        if (currentSpeedMps == null || currentSpeedMps <= 0.0d) {
            return null;
        }
        return (unitDistanceMeters() / currentSpeedMps).toNumber();
    }

    function formatMmSs(totalSeconds) {
        if (totalSeconds == null) {
            return "--:--";
        }
        if (totalSeconds < 0) {
            totalSeconds = -totalSeconds;
        }
        var m = totalSeconds / 60;
        var s = totalSeconds % 60;
        return m.format("%d") + ":" + s.format("%02d");
    }

    function formatHhMmSs(totalSeconds) {
        if (totalSeconds == null) {
            return "-:--:--";
        }
        var h = totalSeconds / 3600;
        var m = (totalSeconds % 3600) / 60;
        var s = totalSeconds % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%d") + ":" + s.format("%02d");
    }

    function formatDistanceUnit() {
        return isMetric() ? "km" : "mi";
    }
}
