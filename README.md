# Enterm

**A native macOS canvas for AI coding agents that still feels like a terminal.**

Enterm runs the official coding CLIs (Claude Code, Codex, Gemini, Antigravity, opencode, Grok, GitHub Copilot, Cursor, or one you add yourself) exactly as they ship, side by side on one pannable canvas. Your sessions keep running when you quit the app, your config files stay untouched, and you can follow and approve the work from your iPhone. It is free, open source and built to sit at 0% CPU when nothing is happening.

Türkçe: [README.tr.md](README.tr.md)

![Enterm: agents side by side on the canvas](docs/media/hero.gif)

## Why Enterm

- **Vendor-neutral.** Use whichever agent fits the task, or several at once. No account, no subscription, no lock-in.
- **Official CLIs, unmodified.** Enterm wraps the programs you already use; it does not patch, proxy or reimplement them.
- **Sessions survive quit.** A background service (`entermd`) owns the terminals, so closing the window does not stop the work.
- **A canvas, not a tab strip.** Every agent and terminal is a box you can tile, move, resize and group, organized into project tabs.
- **Your phone in the loop.** Pair an iPhone with end-to-end encryption and answer permission requests from the lock screen.
- **Light by design.** Nothing animates or polls while idle. A feature you do not use costs nothing.

## Features

### Race

![Two agents racing on the same task, each in its own worktree](docs/media/race.png)

Give one task to several agents and keep the best result. Pick two or three of Claude Code, Codex and Gemini; each gets its own git worktree branched from the same commit and the same instructions, so the race is fair. The racers open side by side in their own tab, each with a live lane showing elapsed time, files changed and lines added and removed, and a runner that moves toward the flag. Medals mark the finishing order.

When everyone is done, the results page shows each entrant's diff and can run the project's test command per entrant (detected from `Package.swift`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml` and others, or one you type). **Pick Winner** merges that branch into your main folder, closes the other boxes and removes every worktree and branch the race created. Your main folder is not touched until you pick. Start one from the command palette or the action menu with **Start a Race**.

![Race results with tests and Pick Winner](docs/media/race-results.png)

### Timeline

![Timeline replay of a race](docs/media/timeline.png)

An animated replay of what an agent did, read from the CLI's own transcript (Claude Code and Codex). Each agent gets a lane with colored marks for prompts, replies, edits, commands and reads; playback lights up the files as they are touched, and long pauses are shortened so the replay shows work, not waiting. A race replays all of its lanes together. **Save as HTML** exports the replay as a single self-contained file you can share; it includes the prompts and commands, so check it before you send it.

### Canvas and projects

- Sessions and views are boxes on a pannable canvas: tile them, move them freely, resize, group, save layouts, undo.
- Project tabs filter the canvas to one project; **All** shows every box. A session in another project keeps running.
- Permission questions light up the box and collect in one place.
- Five-hour and weekly usage limits for Claude Code and Codex on the status line.
- A board of cards assigned to agents: moving a card to **In Progress** sends it to its agent, and the agent reports back.
- Untitled boxes show the program's own session title; the ports a session listens on appear on the box.
- Chat view (`⌘⇧M`) shows a session as a conversation, read from the CLI's own transcript.
- Local dictation with whisper.cpp, which runs only while you dictate.
- Preset skill packs (video, software, image) you switch on in Settings, loaded per session without writing to `~/.claude`. See [`skills/`](skills/).
- `enterm://` links open a folder with a program and a task, a session, a settings page or the board. A link that would start a program asks first.

### Agents drive the canvas (MCP)

A local MCP bridge lets agents work the canvas themselves: read its state, open boxes (now or queued for later), set up a team, open a git worktree, close the boxes they opened, add and move board cards, and show or edit content. Draw a line between two boxes to share context. Tools that open boxes require the "assign work to another agent" permission on the session's permission card, and only you can move a card to Done.

### Phone

An iPhone companion app pairs with your Mac through a QR code: both sides derive a shared secret with X25519 and you compare a six-digit number. The relay in between only ever sees encrypted bytes, and every connection uses a fresh key. From the phone you can follow sessions (including Claude Code and Codex sessions as a conversation), start a new shell, approve or deny permission requests from the lock screen, and watch progress in a Live Activity.

<!-- TODO: link the iPhone app (App Store or TestFlight) once it is public -->

### Built-in views

Alongside terminals, the canvas holds a web browser, web pages, notes, a whiteboard, a file browser, video, and iOS Simulator and Android emulator boxes (tap, swipe and type on Android through `adb`). Agents can use an optional Safari window with per-site permission.

## Install

Requires macOS 14 (Sonoma) or later.

**DMG.** Download the latest release from [GitHub Releases](https://github.com/enmerasoftware/enterm/releases/latest), open the DMG and drag Enterm into Applications. Releases are signed with a Developer ID, notarized by Apple, and update themselves through Sparkle.

**Homebrew.**

<!-- TODO: confirm the cask is published in enmerasoftware/homebrew-tap (Casks/enterm.rb) before launch -->

```bash
brew install --cask enmerasoftware/tap/enterm
```

Then install the agents you want to use (for example Claude Code or Codex) the way their vendors describe. Enterm finds them on your `PATH`.

## Build from source

Requires Xcode at `/Applications/Xcode.app`.

```bash
scripts/bundle.sh release
open build/release-$(git rev-parse --short HEAD)/Enterm.app
```

Run the tests with:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

`DEVELOPER_DIR` points Swift at the full Xcode toolchain, which the tests need, even if `xcode-select` is set to the Command Line Tools. A debug build for local testing: `scripts/bundle.sh debug build/test`.

Repository layout:

- `Sources/EntermCore`: the core, with no AppKit, UIKit or SwiftUI; the iOS app builds on it.
- `Sources/entermd`: the session service that owns the pseudo terminals.
- `Sources/enterm`: a small command for shell integration and hooks, plus the local MCP bridge.
- `Sources/EntermApp`: the macOS app. Canvas and terminals in AppKit, pages and dialogs in SwiftUI.
- `enterm-ios/`, `relay/`: the iPhone app and its encrypted relay.
- `skills/`: the preset skill packs.

Maintainer notes (internals, test driver, release process) are in [docs/MAINTAINERS.md](docs/MAINTAINERS.md) (Turkish).

## Privacy and security

- **No config edits.** Enterm never writes to `~/.zshrc`, `~/.claude`, `~/.codex` or any other configuration. Integration arrives through launch arguments and environment variables.
- **No tokens.** Your subscription tokens stay inside the official CLI and never reach Enterm. A second account lives in the CLI itself through `CLAUDE_CONFIG_DIR` or `CODEX_HOME`.
- **End-to-end encrypted phone.** Pairing uses X25519 with a six-digit comparison; the relay only carries encrypted bytes.
- **Local by default.** Sessions, transcripts and the MCP bridge stay on your Mac. Enterm itself goes online for things you can see: update checks, the dictation model or an agent's official installer when you ask for them, web pages you open, and, once you pair a phone, encrypted traffic through the relay. The agents talk to their own vendors exactly as they do in a plain terminal.
- **Permissions you can see.** By default each CLI asks its own questions as it would in a plain terminal; stricter templates let Enterm's permission card decide.

Please report vulnerabilities privately, see [SECURITY.md](SECURITY.md).

## Languages

The interface is available in English and Turkish, following your Mac's language or the choice in Settings.

The code is written in Turkish, and English is a table, [`Resources/en.json`](Resources/en.json), keyed by the Turkish source text. Built text uses `%@` for the parts (`"Ekip %@"` → `"Team %@"`). After adding or changing on-screen text, run `scripts/strings.py`: it lists every string without English, and CI runs the same check. Strings that are not on-screen text (commands, identifiers) go into `Resources/en-same.json`.

Adding a third language means a new table next to `en.json` and a small change to the bundle step and the language list, so please open an issue first and we will set it up together. Details are in [CONTRIBUTING.md](CONTRIBUTING.md#text-on-screen).

## Contributing

Issues and pull requests are welcome, in English or Turkish. A new skill is the easiest first contribution. Read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

MIT, see [LICENSE](LICENSE).
