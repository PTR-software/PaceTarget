# Working in this repo

This is a Garmin Connect IQ (Monkey C) watch app. Before doing anything else:

1. Read `README.md` (setup, build/run, project layout).
2. Read `CHANGELOG.md` — it holds decision history and known tooling gotchas that aren't obvious from the code alone. Check it before re-deriving something (e.g. simulator quirks, why `WatchUi.Picker` isn't used) or before repeating a mistake already logged there.

**When you make a decision or a non-trivial change, add an entry to `CHANGELOG.md` in the same turn.** Documentation is treated as a first-class part of this project, not an afterthought — the goal is that a future session (or person) with zero memory of this conversation can get full context from `README.md` + `CHANGELOG.md` + `docs/PRD.md` alone.

Don't edit `docs/PRD.md` after the fact to match implementation reality — it's kept as the original requirements doc for historical reference. Divergences go in `CHANGELOG.md` instead.

## Quality gate: own it before handing off

The user can't see the code and often can't verify simulator behavior easily either (no screen access from this environment historically) — every round of "looks done, please test" costs them real time. Before saying a change is ready for the user to test:

1. **Compiling clean is not sufficient.** It only proves the syntax is valid, not that the change does what was asked.
2. **Always rebuild AND actually push/deploy the change** (`scripts/run-sim.sh` or manual `monkeyc` + `monkeydo`) before reporting anything as ready. A real incident: a full round of UI/interaction fixes was compiled successfully but never redeployed, and the user spent a testing cycle on stale code, re-reporting a bug ("tap still works") that had already been fixed in source. Compiling is not shipping.
3. **Self-verify whatever can be self-verified without the user's eyes**: grep to confirm a removed/added code path is actually there (not just "should be" from memory of the edit), sanity-check any non-trivial math independently (e.g. a coordinate/angle formula) before trusting it, re-read the actual diff rather than assuming an edit did what was intended.
4. **Know the difference between "I fixed the code" and "I confirmed the fix."** State plainly which one applies. If something can only be confirmed visually (a layout, a color, an animation) and there's no way to see it this session, say so explicitly instead of implying it's verified.
5. Watch for **library/framework default behavior that contradicts intuition**. Concrete example from this project: `Toybox.WatchUi.BehaviorDelegate` deliberately fires the *same* `onSelect()` for both a physical button press and a plain touchscreen tap — the distinction is erased by the framework before app code sees it, so no amount of overriding `onTap` can separate them. The actual physical-button-only hook is `onKey(keyEvent)` checked against `Ui.KEY_ENTER`, which the SDK docs describe explicitly as firing only for a real button press. This took two wrong guesses and a debug-log session to find — when a fix doesn't behave as expected, suspect a wrong mental model of the framework before suspecting the user is misreporting, and reach for a `Sys.println` in the actual callback sooner rather than reasoning from memory/docs a second time.
6. **Bump `Globals.APP_VERSION` (and `manifest.xml`'s version) on every redeploy**, even mid-session during rapid iteration — it's the only reliable way for the person testing to confirm the build on screen is the one that was just pushed, not a stale one from an earlier round. Skipping this once already cost a round of confusing "did my fix even land" back-and-forth.
