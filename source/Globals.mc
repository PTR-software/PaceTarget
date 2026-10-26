module Globals {
    // Keep in sync with manifest.xml's <iq:application version="..."> - there's
    // no runtime API to read the manifest version, so this is the source of
    // truth for on-screen display. Semver: patch = bugfix only, minor = new
    // backwards-compatible feature, major = breaking change.
    // RULE: bump the patch version on every redeploy during iterative fixing,
    // even mid-session - it's the only reliable way for the person testing to
    // confirm they're looking at the build that was actually just pushed,
    // rather than a stale one from an earlier round.
    const APP_VERSION = "1.8.2";

    var targetDistanceMeters = 5000.0d;
    var targetTimeSeconds = 1500;

    // Scratch state while walking the hour -> minute -> second entry flow.
    var tmpHours = 0;
    var tmpMinutes = 0;

    // Count of views pushed since the root DistanceMenuView (custom-distance/
    // hour/minute/second entry screens - NOT StartConfirmView/RunView, which
    // replace rather than stack via switchToView). Reset to 0 whenever a
    // fresh DistanceMenuView is created. Lets returnToStartScreen() (see
    // SaveConfirmMenu.mc) unwind the exact right number of views instead of
    // guessing a fixed depth.
    var entryStackDepth = 0;

    // Tuning params (FR6/FR7) - exposed here so a future settings screen can adjust them.
    var paceBufferSecPerKm = 10;
    var trendWindowSeconds = 20;
    var adjustStepSeconds = 60;
    var alertRepeatSeconds = 15;
    // Too-fast re-fire cadence (FR6 extension, 2026-08-24) - deliberately
    // separate from alertRepeatSeconds so slow/fast buzz frequency can be
    // tuned independently even though they happen to both start at 20s.
    var fastAlertRepeatSeconds = 20;
}
