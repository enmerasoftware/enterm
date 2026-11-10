# Enterm

A canvas for AI coding agents that still feels like a terminal. Enterm runs the official programs (Claude Code, Codex, Antigravity, Gemini, opencode, Grok, GitHub Copilot, Cursor, or one you add yourself) exactly as they ship, side by side on one surface. macOS today.

Three rules: it stays light, it never edits your config files, and a feature you do not use costs nothing.

Open source and free under the MIT license (`LICENSE`). Türkçe: [README.md](README.md).

## Download

Latest release: [github.com/enmerasoftware/enterm/releases/latest](https://github.com/enmerasoftware/enterm/releases/latest). Open the DMG and drag Enterm into Applications. Releases are signed with a Developer ID and notarized by Apple, and update themselves through Sparkle.

## What it does

- **Sessions on a canvas:** every agent and terminal is a box. Tile them, move them freely, resize, group, save layouts, undo.
- **Projects as tabs:** a tab filters the canvas to one project; "All" shows every box together.
- **Links between agents:** draw a line from one box to another to share context through a local MCP bridge. Any box can link to any other.
- **Sessions survive the window:** a background service owns the terminals, so closing the app does not stop the work.
- **Approvals in one place:** permission questions light the box and collect in one inbox.
- **Usage and limits:** five-hour and weekly limits for Claude Code and Codex on the status line.
- **Board:** cards assigned to agents; moving a card to "Doing" sends it to its agent, the agent reports back.
- **Chat view, local dictation (whisper.cpp), phone companion (iOS),** a browser, notes and a whiteboard on the canvas.
- **Preset skills:** ready-made video, software and image skills you switch on in Settings, loaded per session without touching `~/.claude`. See `skills/`.

## Build

```bash
scripts/bundle.sh release
open build/release-$(git rev-parse --short HEAD)/Enterm.app
```

Requires Xcode (`/Applications/Xcode.app`). Tests:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Layout

- `Sources/EntermCore`: core without AppKit, UIKit or SwiftUI; the iOS client builds on it.
- `Sources/entermd`: session service. Owns the pseudo terminals; sessions outlive the app.
- `Sources/enterm`: small command used by shell integration and hooks, plus the local MCP bridge between agents.
- `Sources/EntermApp`: the macOS app. Canvas and terminals in AppKit, pages and dialogs in SwiftUI.
- `Sources/CPTY`: a `forkpty` wrapper.
- `skills/`: the preset skill packs.
- `enterm-ios/`, `relay/`: phone app (open `enterm-ios/EntermPhone.xcodeproj` in Xcode) and its encrypted relay.

What Enterm never touches: `.zshrc`, `~/.claude`, `~/.codex`. Integration arrives through launch arguments and environment variables. Subscription tokens never reach Enterm; a second account lives in the official program through `CLAUDE_CONFIG_DIR` or `CODEX_HOME`.

## Contributing

Issues and pull requests are welcome, and a new skill is the easiest first contribution. Read [CONTRIBUTING.md](CONTRIBUTING.md) first. The interface is in Turkish today; translation help is welcome.

## Security

Please report vulnerabilities privately, see [SECURITY.md](SECURITY.md).
