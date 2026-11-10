# Contributing to Enterm

Thanks for helping. Türkçe ya da İngilizce yazabilirsiniz; issues and pull requests in Turkish or English are both fine.

## Ground rules

These three come before any feature:

1. **Light.** Nothing runs while idle. A new feature that polls, animates or keeps a process alive needs a reason in the pull request.
2. **Hands off the user's files.** Enterm never edits `.zshrc`, `~/.claude`, `~/.codex` or any other configuration. Integration goes through launch arguments and environment variables.
3. **Official programs unchanged.** Claude Code, Codex and the others run as they ship. Enterm wraps, it does not patch.

## Building and testing

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
scripts/bundle.sh debug build/test
open build/test/Enterm.app
```

`EntermCore` has no AppKit, UIKit or SwiftUI; keep it that way so the iOS client can use it. Logic that can be tested goes there, with a test in `Tests/EntermCoreTests`.

## Pull requests

- One topic per pull request, with a sentence on why.
- Run `swift test` before opening it; CI runs it too.
- For interface changes attach a screenshot in light and dark mode.
- Interface text is Turkish, in title case for buttons and labels (`Yeni Oturum`, `Kutuyu Kapat`). Code, comments and commit messages are English.

## Adding a skill

Skills are the easiest first contribution. Each one is a folder under `skills/<pack>/<name>/` with a `SKILL.md`:

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
- Your own work or something with a license that allows redistribution. Name the source and license in the skill if it is adapted.
- Add the skill to the pack's list in `skills/README.md`.

## Reporting bugs

Use the issue form. Include the Enterm version (Settings → About), macOS version, which program the session ran, and what you expected.
