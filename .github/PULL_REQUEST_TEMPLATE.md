## What changed and why?

<!-- One topic per pull request. A sentence or two on the problem and how this solves it. Link the issue: "Fixes #123". -->

## How was it tested?

<!-- Tests added, commands run, what you tried by hand (scripts/run-test.sh, the iPhone simulator, the relay). -->

## Screenshots

<!-- For interface changes: light and dark mode, and the screen in English and Turkish. Delete this section otherwise. -->

## Checklist

- [ ] `swift test` passes (and `node --test relay/server.test.mjs` if the relay changed)
- [ ] New core logic is in `EntermCore` with a test in `Tests/EntermCoreTests`
- [ ] `scripts/strings.py` lists nothing: new on-screen text has English in `Resources/en.json` (or is in `Resources/en-same.json`)
- [ ] Interface changes: screenshots in light and dark mode, checked in both English and Turkish
- [ ] Docs, `skills/README.md` and the **Unreleased** section of `CHANGELOG.md` are updated where behaviour changed
- [ ] Nothing new runs while idle (or the reason and a `scripts/measure.sh` result are above)
- [ ] No user configuration files are edited and the official programs run unchanged
