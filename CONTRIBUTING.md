# Contributing to Enterm

Thanks for helping. Issues and pull requests are welcome in English or Turkish
(Türkçe ya da İngilizce yazabilirsiniz).

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md). Security problems go through the
[security policy](SECURITY.md), never a public issue. Questions belong in [SUPPORT.md](SUPPORT.md)'s
channels rather than the issue tracker.

## Ground rules

These three come before any feature:

1. **Light.** Nothing runs while idle. A new feature that polls, animates or keeps a process alive needs a
   reason in the pull request. Motion runs only when something happens, and stops while the window is
   hidden, in Low Power Mode or with Reduce Motion on.
2. **Hands off the user's files.** Enterm never edits `.zshrc`, `~/.claude`, `~/.codex` or any other
   configuration. Integration goes through launch arguments and environment variables.
3. **Official programs unchanged.** Claude Code, Codex and the others run as they ship. Enterm wraps, it
   does not patch, and it never handles their tokens.

## Project layout

| Path | What lives there |
| ---- | ---------------- |
| `Sources/EntermCore` | The UI-free core: sessions, permissions, pairing and encryption, localization, transcripts, race and timeline logic. No AppKit, UIKit or SwiftUI, so the iOS app can use it. |
| `Sources/entermd` | The session service. It owns the pseudo terminals, keeps sessions alive when the app quits and exits when there is nothing left to do. Also phone pairing (`PhoneCenter.swift`). |
| `Sources/enterm` | The small command the shell integration and agent hooks call, plus the local MCP bridge between agents (`MCPServer.swift`). |
| `Sources/EntermApp` | The macOS app. Canvas and terminals in AppKit, pages and dialogs in SwiftUI. |
| `Sources/CPTY` | A thin `forkpty` wrapper. |
| `Tests/EntermCoreTests` | Unit tests for the core. |
| `enterm-ios/` | The iPhone app, its notification extension and widgets. `project.yml` is the source of the Xcode project. |
| `relay/` | The relay server for the phone (Node, no dependencies), with its tests. |
| `skills/` | Preset skill packs (Video, Software, Image), each a Claude Code plugin. |
| `Resources/` | `Info.plist`, entitlements, icons, shell integration and the language tables (`en.json`, `en-same.json`, `tr.lproj`). |
| `scripts/` | Build, test, measurement and release scripts. |
| `packaging/homebrew/` | The Homebrew cask template. |
| `docs/` | Documentation; `docs/MAINTAINERS.md` has the maintainer notes on internals. |

## Development setup

You need macOS 14 or later, Xcode (15.3 or later, for Swift tools 5.10) and Python 3 for the strings check.
Node is needed only for the relay, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) only for the
iPhone app.

1. Fork the repository and clone your fork.
2. Point the build at Xcode's toolchain, not the Command Line Tools. Either select it once with
   `sudo xcode-select -s /Applications/Xcode.app` or prefix the commands with `DEVELOPER_DIR` as below.
   The scripts set `DEVELOPER_DIR` to `/Applications/Xcode.app/Contents/Developer` themselves when it is not
   set.
3. Run the tests:

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
   ```

4. Build a debug app into `build/test` and open it:

   ```bash
   scripts/bundle.sh debug build/test
   open build/test/Enterm.app
   ```

   `scripts/bundle.sh [debug|release] [output folder]` builds `Enterm.app` from the Swift package. Without a
   folder a build goes to `build/release-<commit>`. Only `build/test` is ever built over, because someone
   may be running any other copy.

`EntermCore` has no AppKit, UIKit or SwiftUI; keep it that way so the iOS client can use it. Logic that can
be tested goes there, with a test in `Tests/EntermCoreTests`.

## Running the test app with the debug driver

A debug build contains a small test driver (compiled only with `ENTERM_TEST_DRIVER`, which debug builds
define). When `ENTERM_DEBUG_DIR` is set, the app runs the commands in `<dir>/cmd` on `SIGUSR1`: `do <command>`,
`type <text>`, `shot <file>`.

```bash
scripts/bundle.sh debug build/test
scripts/run-test.sh fresh          # restart the debug app on a throwaway configuration under /tmp/et
scripts/drive.sh $(cat /tmp/et/pid) /tmp/et "type echo hi\r" "shot /tmp/et/shot.png"
```

- `scripts/run-test.sh [fresh] [seconds to wait]` starts `build/test/Enterm.app` with a temporary `HOME`,
  its own `ENTERM_HOME` and socket, `ENTERM_DEBUG_DIR=/tmp/et` and `ENTERM_START_TERMINAL=1` (skip the tour
  and start with a terminal). `fresh` also wipes the previous test configuration. The app log goes to
  `/tmp/et/app.log`.
- Tests use a fake `claude` and the temporary `HOME`, so your real configuration is never touched.
- Wait until the app is up before signalling it: a `SIGUSR1` that arrives before the driver is ready ends
  the process.
- `scripts/check-keys.sh` checks that keys the window uses never reach the terminal, and
  `scripts/test-bridge.sh` checks the MCP bridge (link rules, delegation, reports) against a running test
  service.
- `scripts/measure.sh [seconds]` measures the idle CPU and memory of a running Enterm. Use it when a change
  could cost something while idle, and paste the result into the pull request.

## The iPhone app

The Xcode project is generated from `enterm-ios/project.yml` with XcodeGen
(`brew install xcodegen`); do not edit `EntermPhone.xcodeproj` by hand.

```bash
xcrun simctl list devices available        # pick a simulator id
scripts/build-ios.sh <simulator id>         # generates the project, builds, prints the .app path
xcrun simctl install <simulator id> <printed .app path>
```

To work in Xcode, run `xcodegen generate --spec project.yml` inside `enterm-ios/` and open
`enterm-ios/EntermPhone.xcodeproj`. The iPhone app targets iOS 17.

## The relay

```bash
node relay/server.mjs                 # listens on 127.0.0.1:8787 by default
node --test relay/server.test.mjs     # the tests CI runs
```

Its settings are environment variables, listed in `relay/README.md`. The debug app started by
`scripts/run-test.sh` uses `ws://127.0.0.1:8787`.

## Text on screen

The app is written in Turkish and shown in English on any Mac or iPhone that is not set to Turkish, or when
English is chosen in Settings. English lives in `Resources/en.json`, keyed by the Turkish text; built text
uses `%@` for the parts (`"Ekip %@"` → `"Team %@"`). The same table serves the Mac and the iPhone.

After adding or changing text, run `scripts/strings.py`: it lists every string without English. Add each
one to `Resources/en.json`, or to `Resources/en-same.json` when it is not on-screen text (a command, an
identifier). `scripts/strings.py --json` prints the missing ones as a JSON object ready to fill in. CI runs
the same check (`scripts/strings.py --check`). A word with two meanings takes a context:
`L("Açık", context: "tema")` reads `"tema::Açık"`.

Interface text in the code is Turkish, in title case for buttons and labels (`Yeni Oturum`,
`Kutuyu Kapat`); its English in `en.json` is in title case too (`New Session`). Code, comments and commit
messages are English.

## Coding style

There is no formatter or linter configuration; follow the code around you. In practice:

- **Comments say why, in plain sentences.** A comment explains a decision, a limit or a trap
  ("Socket paths have a 104 byte limit, so the socket lives in a short per-user directory."), not what the
  next line does. Types and public functions get a `///` sentence on what they are for.
- **Unwrap safely.** Prefer `guard let` and `if let`; force unwraps and `try!` are rare and only where the
  value cannot be missing. `try?` is fine where a failure has an obvious fallback.
- **Nothing on a timer.** Work in response to events. If something has to look again, it looks a few times
  and stops (see `PortScan.swift`) rather than polling.
- **Keep the core portable.** Anything testable without a window belongs in `EntermCore`, with a test.
- **Names in English.** Types, functions and files are English. Some names that agents and users see stay
  Turkish (for example the MCP tool names such as `tuval_durumu`); do not rename them in passing.
- **Swift 5 language mode**, matching `Package.swift`.

## Commit messages

Look at `git log` for the tone:

- One summary line in the present tense, written as what the change does, with several changes joined by
  commas: `Keep a closed side pane from taking clicks meant for the boxes beside it`,
  `Check for updates from settings, mark a waiting version on the top bar, 0.1.2`.
- A release commit ends its summary with the version (`..., 0.1.5`).
- Larger changes add a blank line and short bullet points.
- No ticket prefixes or emoji. Say what the user notices, not which files moved.

## Pull requests

- One topic per pull request, with a sentence on why.
- Run `swift test` before opening it; CI runs the core tests, the relay tests and the strings check on
  every pull request.
- Run `scripts/strings.py` when you changed any on-screen text, and add the English.
- For interface changes attach screenshots in light and dark mode, and check the screen in both English
  and Turkish.
- Update the docs, `skills/README.md` or `CHANGELOG.md` (under **Unreleased**) when behaviour changes.
- Mention anything that runs while idle, and the `scripts/measure.sh` result if it could.

The pull request template has the checklist.

## Adding a skill

Skills are the easiest first contribution. Each pack under `skills/<pack>/` is a Claude Code plugin
(`.claude-plugin/plugin.json` plus `skills/`), and each skill is a folder
`skills/<pack>/skills/<name>/` with a `SKILL.md`:

```markdown
---
name: video-subtitles
description: Burn or attach subtitles to a video with ffmpeg and whisper.cpp. Use when the user wants subtitles, captions or a transcript for a video file.
---

# Steps the agent follows
...
```

- `description` decides when the agent picks the skill: say what it does and when to use it.
- Keep the body short and concrete: commands, checks, what "done" looks like.
- Only tools the user can install freely. Say how to check that a tool exists before using it.
- Your own work or something with a license that allows redistribution. Name the source and license in the
  skill if it is adapted.
- Add the skill to the pack's list in `skills/README.md`.
- Try it without Enterm: `claude --plugin-dir skills/<pack>`, then `/<pack>:<name>`.

## Good first issues

Issues labelled [`good first issue`](https://github.com/enmerasoftware/enterm/labels/good%20first%20issue)
are small and well described. Other good starting points:

- A new skill, or a better one, in an existing pack.
- Better English in `Resources/en.json`: clearer wording, consistent names, title case.
- A test in `Tests/EntermCoreTests` for core logic that has none.
- Documentation fixes, and reproductions for open bugs.

Comment on an issue before starting larger work, so two people do not build the same thing.

## Reporting bugs

Use the issue form. Include the Enterm version (Settings → About), the macOS version, which program the
session ran, and what you expected.

## How releases work

Releases are made by the maintainers from a Mac that holds Enmera's signing identity and keys; this is here
so you know where your change ends up.

1. Raise `CFBundleShortVersionString` in `Resources/Info.plist`, move the **Unreleased** entries in
   `CHANGELOG.md` under the new version, and commit.
2. `scripts/distribute.sh` builds from a clean commit, signs with Developer ID, has Apple notarize it and
   writes `build/dist-<commit>/Enterm-<version>.dmg`. The notarization credentials come from the `enterm`
   notarytool profile (`ENTERM_NOTARY_PROFILE` changes it).
3. `scripts/publish.sh <dmg> "release notes"` creates the GitHub release on that commit and uploads the DMG
   with an `appcast.xml` signed by the Sparkle key in the Keychain. Installed apps find updates through
   `releases/latest/download/appcast.xml`.
4. `scripts/cask.sh <dmg>` writes `packaging/homebrew/enterm.rb`, which goes into
   `enmerasoftware/homebrew-tap` as `Casks/enterm.rb`.

More detail is in [docs/MAINTAINERS.md](docs/MAINTAINERS.md).

## License

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
