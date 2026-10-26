# Contributing to Pace Target

Thanks for your interest in contributing! This app is primarily tested on a Garmin Venu 3, so help testing on other Connect IQ devices is especially welcome.

## Getting started

1. Follow the setup instructions in [README.md](README.md) to install the Connect IQ SDK, OpenJDK, and generate a developer signing key.
2. Fork this repo and clone your fork.
3. Make your changes in a feature branch.

## Building and testing

- Build + run in simulator: `./scripts/run-sim.sh [device]` (defaults to `venu3`).
- Build manually: see README for `monkeyc` usage.
- Test on real hardware by sideloading a built `.prg` to your watch.

## Adding support for a new device

If you want to add support for a watch you own/test on:

1. Check the device ID in the Connect IQ SDK (or Garmin's device list).
2. Add it to `<iq:products>` in `manifest.xml`.
3. Build and test with `./scripts/run-sim.sh <device>`.
4. Open a PR describing the device, what you tested, and any screen/layout quirks you had to work around.

## Code style

- Follow the existing style (clear naming, small focused files).
- This app uses physical-button-first input (`onKey(KEY_ENTER)`) on touch devices like Venu 3 — see README/CHANGELOG for context. Be careful not to reintroduce `onSelect`/`onTap` for confirm actions without understanding that distinction.
- Keep UI logic in Views/Delegates, pure math in `PaceMath.mc`, shared state/tuning in `Globals.mc`.
- If you make a non-trivial change or design decision, update `CHANGELOG.md` in the same PR (matching the existing style).
- Avoid leaving `Sys.println` debug logs in merged code; use a debug flag if you need them temporarily.

## Reporting bugs

Open an issue with:
- Device model + Connect IQ firmware version
- Steps to reproduce
- Expected vs actual behavior
- Simulator logs or screenshots if possible

## Pull requests

- Keep PRs focused and small where possible.
- Include a short description of what/why.
- If the change affects layout on round vs rectangular screens, call it out.
- Make sure it builds cleanly for at least the devices you claim to support.

Thanks again!
