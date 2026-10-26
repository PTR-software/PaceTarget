# Pace Target

A Garmin Connect IQ watch app for runners: set a distance and a target finish time, and it tracks the pace required to hit that time live, buzzing when you fall too far behind. Records a real running activity that syncs to Garmin Connect, same as the native Run app.

**Open source (MIT License).** Tested primarily on Garmin Venu 3. Contributions to add support for other Connect IQ devices are very welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

- **Requirements & scope:** [`docs/PRD.md`](docs/PRD.md)
- **Decision history & known issues:** [`CHANGELOG.md`](CHANGELOG.md) — **read this before making changes**, especially "Known simulator/tooling issues" if something in the simulator seems broken.

Documentation is a first-class part of this project: when you make a decision or a non-trivial change, log it in `CHANGELOG.md` in the same sitting. The goal is that anyone (or any AI session) picking this up cold can get full context from these three files without re-deriving anything from scratch.

## Project layout

```
manifest.xml            App id, permissions, supported devices, min SDK version
monkey.jungle           Build config (source/resource paths)
source/                 Monkey C source
  PaceTargetApp.mc       App entry point
  DistanceMenuView.mc     Setup: distance preset menu (Menu2)
  EntryFlow.mc            Setup: custom-distance -> hours -> minutes -> seconds screens, chained
  NumberEntryView.mc      Custom self-drawn number-entry view/delegate (see below - why not WatchUi.Picker)
  GpsAcquireView.mc       Setup: GPS-activation gate shown before StartConfirmView, waits for a usable fix
  RunView.mc / RunDelegate.mc   Live run screen: session/timer, required pace, total time, distance, delta, pace gauge
  SaveConfirmMenu.mc      Stop -> Save/Discard/Resume menu
  PaceAlert.mc            Too-slow detection + vibrate (buffer + trend-window + re-arm logic)
  PaceMath.mc             Pure pace/time/distance math + formatting, unit-aware
  Globals.mc              Shared mutable state + tuning parameters
resources/               Strings, drawables (launcher icon)
docs/PRD.md              Product requirements
scripts/run-sim.sh       Rebuild + relaunch simulator + push, in one command
scripts/*.gpx            Synthetic constant-pace GPX tracks for deterministic sim testing
```

**Why no `WatchUi.Picker`?** It was tried first and abandoned — see the 2026-07-28 entries in `CHANGELOG.md` for the full story. Short version: its layout/touch behavior isn't documented well enough to control reliably, it caused three separate crashes, and it wasn't fixable without seeing exactly what it renders (which wasn't possible in this dev environment). `NumberEntryView.mc` is a small, fully self-drawn replacement.

**Interaction model — physical button only, deliberately.** Every confirm/adjust action (entry-screen confirm, mid-run tighten-goal) is bound to `onKey()` checked against `Ui.KEY_ENTER`, not `onSelect()` or `onTap()`. This was a hard-won finding: `BehaviorDelegate` fires the *same* `onSelect()` for both a real physical button press and a plain touchscreen tap — the distinction is erased before app code sees it — so `onKey()` is the only way to make an action genuinely button-only on a touch-primary device like the Venu 3. See the 2026-07-28 "round 3" changelog entry before changing any input handling in `NumberEntryView.mc` or `RunDelegate.mc`.

**On-screen version number.** The distance-menu screen's title shows `Pace Target vX.Y.Z`, sourced from `Globals.APP_VERSION` (there's no runtime API to read `manifest.xml`'s version, so it's a hand-kept constant). Bump this on every redeploy during iterative fixing, not just at the end of a batch — it's the only reliable way to confirm a build actually landed.

## One-time setup

1. Install the Connect IQ SDK Manager: `brew install --cask connectiq-sdk-manager`, then launch `/Applications/SdkManager.app` and use it to download the SDK + device support (accept the Garmin developer agreement, sign in).
2. Install a JVM — `monkeyc`/`monkeydo` need one and it isn't bundled: `brew install openjdk`.
3. Generate a developer signing key (one-time; SDK Manager may also offer to do this):
   ```
   KEYDIR="$HOME/Library/Application Support/Garmin/ConnectIQ"
   openssl genrsa -out "$KEYDIR/developer_key.pem" 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in "$KEYDIR/developer_key.pem" -out "$KEYDIR/developer_key.der" -nocrypt
   ```

## Build & run

```
./scripts/run-sim.sh          # builds for venu3, relaunches the simulator, pushes
./scripts/run-sim.sh fr255    # or any device id declared in manifest.xml
```

This script exists because the manual sequence (kill stale sim → build → relaunch → wait for it to settle → push) is fragile and easy to get wrong — see `CHANGELOG.md`'s "Known simulator/tooling issues". If a push seems to hang, **wait it out rather than interrupting it** — interrupting has repeatedly killed the simulator outright instead of resolving anything.

To build manually for a specific device without running the sim:
```
export JAVA_HOME="$(brew --prefix openjdk)/libexec/openjdk.jdk/Contents/Home"
SDKBIN=$(find "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" -maxdepth 1 -iname "connectiq-sdk-mac-*" | sort | tail -1)/bin
KEY="$HOME/Library/Application Support/Garmin/ConnectIQ/developer_key.der"
"$SDKBIN/monkeyc" -f monkey.jungle -o bin/pace-target-<device>.prg -d <device> -y "$KEY"
```

## Testing pace/distance in the simulator

The simulator has no manual speed slider. To feed it a known, exact pace:

1. Get the app to the live Run screen (distance → hours → minutes → seconds, confirming each with `KEY_ENTER` / the physical button). After seconds, a **GPS-activation gate** (`GpsAcquireView`) appears — press the button once to start acquiring, then a second time to skip the wait (the simulator won't produce any location fix, and thus never satisfies the gate, until GPX playback is already running — which itself requires being on the Run screen, so in the simulator this is a genuine chicken/egg and the skip press is always needed). Real hardware doesn't have this problem — it waits for an actual fix and proceeds on its own once GPS reports `Position.QUALITY_USABLE` or better.
2. Simulator menu: **Simulation → Activity Data → FIT/GPX Playable File**, browse to one of `scripts/*.gpx`, press ▶.
3. Required pace, total time, distance, and delta should update live; the pace gauge (arc around the bottom of the screen) should track how far current pace is from required.

Don't use **Settings → Set Position** after the recording has already started — it registers as an instant, enormous distance jump. See `CHANGELOG.md` for more simulator gotchas.

## Screenshots

See the [screenshots/](screenshots/) folder for example screenshots. If you'd like to add screenshots for your device, see [screenshots/README.md](screenshots/README.md).

## Real device

Primary test hardware is a **Garmin Venu 3**. Sideloading and Garmin Connect sync haven't been verified end-to-end yet as of the last changelog entry — check `CHANGELOG.md` for current status before assuming it works.

## License

This project is licensed under the [MIT License](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to build, test, and contribute. Help adding/testing support for other Garmin watches is especially appreciated!
