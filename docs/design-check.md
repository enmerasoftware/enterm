# Design check

Enterm runs [ai-design-check](https://github.com/enmerasoftware/ai-design-check) on the project in front of you: rules for what makes an AI-built interface look generated, on the web (React, Vue, Svelte, Blade, HTML; Tailwind, Bootstrap or plain CSS) and in SwiftUI (iOS and macOS), Jetpack Compose, Flutter and React Native apps. Open **Design Check** from the ⋯ menu, the command palette or the canvas menu.

**On this page:** [What it shows](#what-it-shows) · [Actions](#actions) · [The fix skill](#the-fix-skill) · [Requirements](#requirements)

## What it shows

- Errors, warnings and notes, counted, for the focused session's folder.
- Every finding grouped by file, with line, message and rule; filter by area (accessibility, layout, type, visual language, copy…). Click a file to open it; click a rule to read it in `RULES.md`.

Enterm always runs the latest release (`npx --yes @enmera/ai-design-check@latest`), so the rules improve without an Enterm update. Nothing in your project changes until you press a button that says so.

## Actions

| Button | What happens |
|---|---|
| **Check Again** | Runs the checker on the folder |
| **Scan Running Page** | Shown when the focused session listens on a port: `scan http://localhost:<port>` measures the running page at desktop and phone width (contrast, sizes, overlaps, script errors) |
| **Preview Mechanical Fixes** | `--fix --dry-run`: what has one answer (spacing and corners to the scale, very heavy type to bold). **Apply** writes them and checks again |
| **Fix with an Agent** | A new Claude Code session (Codex when Claude Code is missing) in the folder, told to fix the design with the checker and report the counts before and after |
| **Design Race** | The race page with the design task and the checker as the test command: several agents fix the same screen in their own worktrees, and the results show whose version is clean |

## The fix skill

Settings → Skill Packs → **Design · ai-design-check** adds the checker's fix skill to new Claude Code sessions, through the same review as any [Library](library.md) pack. Then ask a session *"fix the design of this screen"*: the agent measures the screen, writes a short brief from your product, repairs it, and shows the count before and after.

## Requirements

Node.js (for `npx`). If it is missing, the page says so: `brew install node`. Code: `Sources/EntermApp/DesignCheck.swift`.
