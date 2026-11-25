# Library

Prompts, race tasks and skill packs in two shelves, shown together on the **Library** page (⋯ menu, command palette, or the canvas menu → *Work Together*) and on [enterm.enmeraapps.com/library](https://enterm.enmeraapps.com/library):

- **Reviewed:** the [`library/`](../library) folder of this repository. Every entry is reviewed before it joins `index.json`.
- **Community:** what people share from Enterm. It is published at once, after automatic checks, and marked *Community · Unreviewed* until a maintainer reviews it.

**On this page:** [Using an item](#using-an-item) · [Skill packs](#skill-packs) · [Sharing](#sharing) · [Community shelf](#community-shelf) · [Safety](#safety) · [Privacy](#privacy) · [Files](#files)

## Using an item

| Kind | What you can do |
|---|---|
| **Prompt** | Read it, pick a program, **Run**: a new session opens in the folder in front of you with the prompt as its first message. **Race It** opens the race page with the prompt as the task. **Copy** puts it on the clipboard. |
| **Race task** | A task meant for several agents at once. **Race It** fills the race page with the task and, when your project has no test command of its own, the task's suggested one. |
| **Skill pack** | **Review Files and Add** downloads the pack, lists every file (the ones that can run something first), and adds it only when you press **Add**. |

**Blanks:** a prompt can have blanks written `${name}` or `${name:default}`. **Run** asks for them first; one left empty takes its default.

**Like** (the heart) counts once per Mac and orders the lists. **Save** (the bookmark) keeps an item on this Mac; saved items also appear in the command palette as *Library: …* and open on the Library page, where they are read before they run. Search matches the title, summary, tags, programs and text in English and Turkish.

The index is read when the page opens, at most every five minutes, and kept in `~/Library/Application Support/Enterm/library.json`, so the Library opens at once and works offline. An item with a field or kind this version does not know is left out; the rest still show.

## Skill packs

A skill pack is a folder in Claude Code plugin form (`.claude-plugin/plugin.json`, `skills/<name>/SKILL.md`) in any public GitHub repository; the Library lists where it lives (`repo`, `path`, `ref`). Enterm downloads the repository archive from `codeload.github.com`, keeps only the pack's folder, and on **Add** copies it to `~/Library/Application Support/Enterm/skills/<id>` and switches it on. New Claude Code sessions get it through `--plugin-dir`, like the packs that ship with the app; nothing is written to `~/.claude`. **Remove** deletes the folder and switches it off. Settings → Skill Packs lists shipped and added packs together.

## Sharing

**Share a Prompt** on the Library page: a title, a one-sentence summary, the text, the programs it works with, up to four tags and, if you like, a name shown with it. A race task also needs its test command. **Share** sends it to the community shelf; once it passes the server's checks it is in everyone's Library and on the website at once. You can take it back from the item's ⋯ menu on the Mac that shared it.

**Suggest on GitHub** in the same window opens a prefilled issue for the reviewed shelf instead. You can also open a pull request that adds a file under `library/prompts/`; see [library/CONTRIBUTING.md](../library/CONTRIBUTING.md).

## Community shelf

- **Checks before publishing:** length and format of every field, programs and tags from the allowed lists, no prompt-injection bait, destructive commands, piping a download into a shell, switching off the agent's permission checks, or anything that looks like a key or token (`library/scripts/rules.mjs`, shared with the reviewed shelf). The same text twice is refused.
- **Limits:** five shares an hour and twenty a day per Mac and per address.
- **Reports:** the ⋯ menu reports an item as harmful, carrying secrets, spam, or not working. After three Macs report an unreviewed item it is hidden until a maintainer looks at it.
- **Review:** maintainers mark items reviewed, hide or delete them on the server's admin page, and can copy an item as a reviewed-library file to move it into `library/`.
- Skill packs are not on the community shelf: they carry code, so they join the reviewed shelf only.

## Safety

- Nothing runs by itself. A prompt starts a session only from **Run**, after you have read it on the page; a skill pack is added only from **Add**, after its files are listed.
- Files that can execute (shell, Python, JavaScript and other scripts, hooks) are listed first in the review, so they get read.
- Community items say *Unreviewed* on the list and above the text until a maintainer reviews them.
- Every reviewed-shelf submission is checked against a checklist: no secrets, no destructive or exfiltrating instructions, no prompt-injection bait, readable skill sources under a permissive licence.
- The repository and pack paths are validated before download; a pack path cannot leave the downloaded archive.

## Privacy

The app talks to `enterm.enmeraapps.com` to read the community shelf and like counts, and when you share, like or report. With each of those it sends a random id made once for this Mac (`library-device`), which says nothing about you. The server keeps what you share, the time, and salted one-way hashes of that id and of your IP address, for limits, likes, reports and taking a share back; nothing else, no trackers. The server's code is in [`site/server.mjs`](../site/server.mjs).

## Files

| Path | What |
|---|---|
| `~/Library/Application Support/Enterm/library.json` | The last index read |
| `~/Library/Application Support/Enterm/library-community.json` | The last community shelf read |
| `~/Library/Application Support/Enterm/library-shelf.json` | Saved items, likes, your shares and added skill packs |
| `~/Library/Application Support/Enterm/library-device` | The random id sent with shares, likes and reports |
| `~/Library/Application Support/Enterm/skills/<id>/` | Skill packs added from the Library |

Code: `Sources/EntermCore/Library.swift` (index, search, shelf, community client, blanks), `Sources/EntermApp/Library.swift` (page, sharing, download, review), `site/server.mjs` (website and community server).
