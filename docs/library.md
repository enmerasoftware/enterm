# Library

Prompts, race tasks and skill packs that people share, in the [`library/`](../library) folder of this repository. Enterm reads its `index.json` and shows it on the **Library** page (⋯ menu, command palette, or the canvas menu → *Work Together*).

**On this page:** [Using an item](#using-an-item) · [Skill packs](#skill-packs) · [Sharing](#sharing) · [Safety](#safety) · [Files](#files)

## Using an item

| Kind | What you can do |
|---|---|
| **Prompt** | Read it, pick a program, **Run**: a new session opens in the folder in front of you with the prompt as its first message. **Race It** opens the race page with the prompt as the task. **Copy** puts it on the clipboard. |
| **Race task** | A task meant for several agents at once. **Race It** fills the race page with the task and, when your project has no test command of its own, the task's suggested one. |
| **Skill pack** | **Review Files and Add** downloads the pack, lists every file (the ones that can run something first), and adds it only when you press **Add**. |

**Save** (the bookmark) keeps an item on this Mac; saved items also appear in the command palette as *Library: …* and open on the Library page, where they are read before they run. Search matches the title, summary, tags, programs and text in English and Turkish.

The index is read when the page opens, at most every five minutes, and kept in `~/Library/Application Support/Enterm/library.json`, so the Library opens at once and works offline. An item with a field or kind this version does not know is left out; the rest still show.

## Skill packs

A skill pack is a folder in Claude Code plugin form (`.claude-plugin/plugin.json`, `skills/<name>/SKILL.md`) in any public GitHub repository; the Library lists where it lives (`repo`, `path`, `ref`). Enterm downloads the repository archive from `codeload.github.com`, keeps only the pack's folder, and on **Add** copies it to `~/Library/Application Support/Enterm/skills/<id>` and switches it on. New Claude Code sessions get it through `--plugin-dir`, like the packs that ship with the app; nothing is written to `~/.claude`. **Remove** deletes the folder and switches it off. Settings → Skill Packs lists shipped and added packs together.

## Sharing

**Share a Prompt** on the Library page opens a prefilled GitHub issue in this repository (title, summary, kind, programs, text). You read it on GitHub before sending; maintainers review it before it joins the index. You can also open a pull request with a new file directly; see the repository's CONTRIBUTING.

## Safety

- Nothing runs by itself. A prompt starts a session only from **Run**, after you have read it on the page; a skill pack is added only from **Add**, after its files are listed.
- Files that can execute (shell, Python, JavaScript and other scripts, hooks) are listed first in the review, so they get read.
- Every submission is reviewed against a checklist: no secrets, no destructive or exfiltrating instructions, no prompt-injection bait, readable skill sources under a permissive licence.
- The repository and pack paths are validated before download; a pack path cannot leave the downloaded archive.

## Files

| Path | What |
|---|---|
| `~/Library/Application Support/Enterm/library.json` | The last index read |
| `~/Library/Application Support/Enterm/library-shelf.json` | Saved items and added skill packs |
| `~/Library/Application Support/Enterm/skills/<id>/` | Skill packs added from the Library |

Code: `Sources/EntermCore/Library.swift` (index, search, shelf, share link), `Sources/EntermApp/Library.swift` (page, download, review).
