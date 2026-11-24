# Changelog

All notable changes to Enterm are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Enterm uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). While the version is below 1.0.0, a minor
release (0.x.0) may change behaviour that earlier versions relied on; patch releases only add and fix.

Downloads and the signed update feed for every version are on the
[releases page](https://github.com/enmerasoftware/enterm/releases).

## [Unreleased]

### Added

- **Library**: prompts, race tasks and skill packs shared in [enmerasoftware/enterm-library](https://github.com/enmerasoftware/enterm-library). Browse, search, save, run a prompt in a new session with one click, race a task, review a skill pack's files and add it, share your own prompt as a prefilled GitHub issue. See [docs/library.md](docs/library.md).
- **Design Check**: runs [ai-design-check](https://github.com/enmerasoftware/ai-design-check) on the focused project, lists findings by file and area, previews and applies mechanical fixes, scans the running page, fixes with an agent, or starts a design race with the checker as the test. See [docs/design-check.md](docs/design-check.md).
- Skill packs added from the Library are given to new Claude Code sessions next to the shipped ones.

## [0.1.5] - 2026-11-23

### Added

- Race: give one task to two or three agents, each in its own git worktree. Live lanes, medals, test
  results per entrant, and merging the winner in one click, also from the phone.
- Timeline: an animated replay of what each agent did, read from its transcript. It can be exported as a
  single HTML file to share.
- English interface on Mac and iPhone, with a language choice in Settings.
- Each project tab remembers its own pan and zoom; pinch and ⌘-scroll to zoom.

### Changed

- Cleaner Mac and iPhone screens: symmetric headers, grouped settings, a tidier details pane and short
  notes in the status line.

### Security

- Updates are signed with a new Sparkle key. Version 0.1.4 cannot verify updates signed with it, so if you
  run 0.1.4, download this version once by hand; later updates arrive in the app as before.

## [0.1.4] - 2026-11-11

### Added

- Claude Code and Codex sessions open as a conversation on the phone: messages, tool steps and a reply box.
  The button at the top right switches to the terminal.

### Changed

- The Mac's terminal no longer shrinks while the phone is looking at a session; the phone shows the Mac's
  size and scrolls it.
- Redesigned phone pairing screen: numbered steps, a large comparison number and a one-line relay setting.
- The relay address defaults to `wss://enterm.enmeraapps.com`.

### Fixed

- Leading and trailing spaces in the relay address are ignored.

## [0.1.3] - 2026-11-10

### Added

- Agents can run the canvas: open boxes, teams and worktrees, add board cards, and show a note or a page.
  Opening a box needs your approval.
- A box shows the port its session listens on (for example `:3000`), the conversation title and the
  `/loop` schedule.
- Settings gained Skill Packs (software, video, image) and a described list of Claude Code commands.
- Gemini, opencode, Copilot and Cursor report their status to Enterm.
- Android emulator in the simulator box.
- `enterm://` links.

### Changed

- Boxes move freely in the All Projects view; the tab of an enlarged box shows as selected.
- Menus were reorganised, and the details pane opens over the canvas.

## [0.1.2] - 2026-11-09

### Added

- Update check in Settings › About. A mark appears at the top right while a new version is waiting.

## [0.1.1] - 2026-11-09

### Added

- Usage limits are shown as bars, with the weekly reset date.
- URLs and paths in the terminal are clickable.
- A queued session announces itself in the middle of the screen.
- A system notification arrives when a job finishes.

### Changed

- The All Projects view is simpler, and tabs no longer widen on hover.

## [0.1.0] - 2026-11-09

### Added

- First public release of Enterm: terminals, agents and notes on one canvas. Shipped as a DMG notarized by
  Apple; later versions update from inside the app.

[Unreleased]: https://github.com/enmerasoftware/enterm/compare/v0.1.5...HEAD
[0.1.5]: https://github.com/enmerasoftware/enterm/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/enmerasoftware/enterm/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/enmerasoftware/enterm/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/enmerasoftware/enterm/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/enmerasoftware/enterm/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/enmerasoftware/enterm/releases/tag/v0.1.0
