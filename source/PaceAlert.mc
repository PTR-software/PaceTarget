using Toybox.Attention as Attention;
using Toybox.System as Sys;

// FR6: vibrate when current pace deviates from required pace by more than a
// buffer, sustained over a trend window, in EITHER direction:
//   - too slow: single long buzz, re-fires every Globals.alertRepeatSeconds
//   - too fast: two short buzzes, re-fires every Globals.fastAlertRepeatSeconds
// (added 2026-08-24 - the original version only had the slow direction).
// Slow and fast are armed/tracked independently (separate _since/_lastFire
// pairs) so a runner drifting from slow to fast doesn't inherit the other
// direction's arm timer or wait out its cooldown. Each direction keeps
// re-firing on its own cadence while still off in that direction, not just
// once - and re-arms for a fresh trend-window wait only after pace recovers
// back inside the buffer.
class PaceAlert {
    var _slowSinceMs = null;
    var _slowLastFireMs = null;
    var _fastSinceMs = null;
    var _fastLastFireMs = null;

    function initialize() {
    }

    // requiredSecPerUnit / currentSecPerUnit are seconds-per-km-or-mile (higher = slower).
    // nowMs is System.getTimer() milliseconds.
    function update(requiredSecPerUnit, currentSecPerUnit, nowMs) {
        if (requiredSecPerUnit == null || currentSecPerUnit == null) {
            _slowSinceMs = null;
            _slowLastFireMs = null;
            _fastSinceMs = null;
            _fastLastFireMs = null;
            return;
        }

        var deviation = currentSecPerUnit - requiredSecPerUnit;
        var isSlow = deviation > Globals.paceBufferSecPerKm;
        var isFast = deviation < -Globals.paceBufferSecPerKm;

        if (!isSlow) {
            _slowSinceMs = null;
            _slowLastFireMs = null;
        } else if (_slowSinceMs == null) {
            _slowSinceMs = nowMs;
        } else {
            var slowDurationSec = (nowMs - _slowSinceMs) / 1000;
            if (_slowLastFireMs == null) {
                if (slowDurationSec >= Globals.trendWindowSeconds) {
                    fireSlow();
                    _slowLastFireMs = nowMs;
                }
            } else {
                var sinceLastSlowFireSec = (nowMs - _slowLastFireMs) / 1000;
                if (sinceLastSlowFireSec >= Globals.alertRepeatSeconds) {
                    fireSlow();
                    _slowLastFireMs = nowMs;
                }
            }
        }

        if (!isFast) {
            _fastSinceMs = null;
            _fastLastFireMs = null;
        } else if (_fastSinceMs == null) {
            _fastSinceMs = nowMs;
        } else {
            var fastDurationSec = (nowMs - _fastSinceMs) / 1000;
            if (_fastLastFireMs == null) {
                if (fastDurationSec >= Globals.trendWindowSeconds) {
                    fireFast();
                    _fastLastFireMs = nowMs;
                }
            } else {
                var sinceLastFastFireSec = (nowMs - _fastLastFireMs) / 1000;
                if (sinceLastFastFireSec >= Globals.fastAlertRepeatSeconds) {
                    fireFast();
                    _fastLastFireMs = nowMs;
                }
            }
        }
    }

    function fireSlow() {
        if (Attention has :vibrate) {
            var vibeData = [ new Attention.VibeProfile(75, 1000) ];
            Attention.vibrate(vibeData);
        }
    }

    // Two short buzzes (vs. slow's one long buzz) so the two directions are
    // distinguishable by feel alone, without looking at the watch. Middle
    // VibeProfile is a 0-intensity gap, not a buzz.
    function fireFast() {
        if (Attention has :vibrate) {
            var vibeData = [
                new Attention.VibeProfile(75, 150),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(75, 150)
            ];
            Attention.vibrate(vibeData);
        }
    }
}
