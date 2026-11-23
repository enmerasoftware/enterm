# Timeline

The timeline is an animated replay of what an agent did: one lane per agent, a colored mark for every prompt, reply, edit, command and read, and a playhead that lights up the marks and the touched files as it passes. It is read from the agent CLI's own transcript file; Enterm records nothing extra for it.

Parsing lives in `Sources/EntermCore/Timeline.swift` (tested in `Tests/EntermCoreTests/TimelineTests.swift`); the page, the player and the HTML export are in `Sources/EntermApp/TimelinePage.swift`.

**On this page**

- [Opening a timeline](#opening-a-timeline)
- [Supported programs](#supported-programs)
- [Event kinds](#event-kinds)
- [How transcripts are parsed](#how-transcripts-are-parsed)
- [Gap compression](#gap-compression)
- [Playback](#playback)
- [HTML export](#html-export)
- [Privacy](#privacy)

## Opening a timeline

| From | Shows |
| --- | --- |
| Command palette → **Timeline** | The focused session |
| Right-click a session's box or tab → **Timeline** (listed once the transcript path is known) | That session |
| Session **Details** (`⌘I`) → **Timeline** | That session |
| **Race Results** → **Replay the Race** | Every racer of the race, one lane each ([race.md](race.md)) |

For a race, each lane uses the live session's transcript if the box is still open, otherwise the transcript path saved in `races.json`, so a race can be replayed after its boxes are closed. The transcript file itself belongs to the agent CLI; if it has been deleted, that lane is empty.

## Supported programs

**Claude Code** and **Codex.** The parser understands their JSON Lines transcript formats. For any other program, or a session whose transcript path is unknown, the page says the timeline appears in Claude Code and Codex sessions.

Enterm learns a session's transcript path from the program's hook events (`transcript_path`). Codex only sends those after you trust Enterm's hooks in Codex's `/hooks` screen ([troubleshooting](troubleshooting.md#codex-status-needs-your-approval)).

The formats are the vendors' own and may change. A line that cannot be read is skipped; parsing never fails.

## Event kinds

| Kind | Color (as in the HTML export) | Meaning | Mark height |
| --- | --- | --- | --- |
| `prompt` | yellow-green | You (or another agent) asked something | full |
| `reply` | light grey | The agent answered in words | 60% |
| `edit` | green | A file was written or changed | full |
| `command` | blue | A shell command ran | 60% |
| `read` | violet | Something was read or searched | 60% |
| `tool` | grey | Any other tool | 60% |

Each event has a time, a kind, a short text (at most 400 characters, first line for commands) and, for edits and reads, a file.

## How transcripts are parsed

`Timeline.parse` reads the file line by line. A line is used only if it is a JSON object with a `timestamp` (ISO 8601, with or without fractional seconds). Lines marked `isMeta` or `isSidechain` are skipped. Text that is empty or starts with `<` (tags the CLIs insert) is dropped.

**Claude Code** (`type` is `user` or `assistant`): a `user` message becomes a `prompt`, an `assistant` message a `reply`. When the content is a list of parts, each `text` part becomes a prompt or reply and each `tool_use` part is classified by tool name:

| Tool | Kind | Text / file |
| --- | --- | --- |
| `Edit`, `MultiEdit`, `Write`, `NotebookEdit` | `edit` | `file_path`, `notebook_path` or `path` |
| `Bash` | `command` | First line of the command |
| `Read`, `Grep`, `Glob`, `LS`, `WebFetch`, `WebSearch` | `read` | The file, pattern, query or URL |
| anything else | `tool` | One-line summary of the tool and its input |

**Codex** (`type` is `response_item`, details in `payload`):

| Payload | Kind | Text / file |
| --- | --- | --- |
| `message` with role `user` / other | `prompt` / `reply` | Each text part |
| `function_call`, `custom_tool_call`, `local_shell_call` whose name contains `patch`, or whose input contains `*** Begin Patch` | `edit` | One event per file in the patch (`*** Update File:`, `*** Add File:`, `*** Delete File:`) |
| other calls of those types | `command` | The command; for `["bash", "-lc", "…"]` the last word, otherwise the words joined |

Events are sorted by time. The **Files** list is every edited file in the order it was first touched.

## Gap compression

Real sessions contain long pauses: you were away, an approval waited, the agent was thinking. To make the replay show work rather than waiting, `Timeline.compressed(gap:)` places events on a track where every pause between two consecutive events is capped at **20 seconds**. The page says so ("Long pauses are shortened to 20 seconds"). The clock on the page and in the export shows this compressed time, not wall-clock time.

## Playback

- The whole replay plays in a fixed duration chosen with **Fast**, **Normal** or **Slow** (10, 25 or 60 seconds), whatever the length of the work. The speed is the compressed length divided by that duration, never slower than the compressed time itself.
- **Play/Pause** (`Space`) and **Restart**. Drag on any lane to scrub.
- The playhead advances about 30 times a second while playing and stops when it reaches the end or you leave the page. Nothing runs while paused.
- Marks before the playhead are drawn at full strength, the rest faded.
- **Feed** shows the last nine events of the selected lane up to the playhead; click a lane's title to select it. **Files** lists edited files with a touch count; the most recent one is highlighted.
- The replay starts by itself once when the page opens, only if [motion](architecture.md#resource-use-and-the-motion-rule) is allowed; otherwise the page opens at the end with everything visible.

## HTML export

**Save as HTML** writes one self-contained file (default name `enterm-replay.html`) that plays the same replay in any browser. It has no server, loads no scripts, fonts or images from anywhere else, and works offline. It has its own Play/Pause, Restart and Fast/Normal/Slow controls, scrubbing, the feed and the files list, and respects `prefers-reduced-motion` (it does not autoplay then).

What the file contains, per lane:

| Included | Not included |
| --- | --- |
| The page title: the lanes' names joined with " · " | Absolute dates and times (only compressed seconds from the start, rounded to 0.1 s) |
| Each lane's name (the box or program name) | Full file paths (only the file name, without folders) |
| For every event: its compressed time, its kind, and its text cut to 160 characters | Replies beyond 160 characters, command output, file contents, diffs |
| For edits and reads: the file name | Anything from outside the transcript |

The data is embedded as JSON in a `<script>` block, with `</` escaped so the data cannot close the script.

## Privacy

The export includes **your prompts, the agent's replies and the commands it ran**, each up to 160 characters, and the names of the files it touched. Prompts and commands can contain secrets, internal hostnames, customer names or paths. The page reminds you of this under the timeline: "The exported file includes prompts and commands; check it before sharing."

Reading the timeline inside Enterm reads the transcript file on your Mac and sends nothing anywhere.
