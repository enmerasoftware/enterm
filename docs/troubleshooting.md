# Troubleshooting

Failure modes that Enterm detects or that follow from how it works, what you see, why, and what to do. Messages are quoted as the English interface shows them.

**On this page**

- Programs: [not installed or not on PATH](#a-program-is-not-installed-or-not-on-path) · [`gemini` not found](#gemini-is-not-found) · [Status Unknown or stuck on Starting](#a-box-says-status-unknown-or-stays-on-starting) · [Claude Code waits at the start](#claude-code-shows-needs-approval-right-after-starting) · [Codex status needs your approval](#codex-status-needs-your-approval) · [Antigravity status](#antigravity-status-needs-your-approval) · [no status or approvals from Claude Code](#claude-code-shows-no-status-limits-or-approvals) · [Gemini status only from the screen](#gemini-status-comes-only-from-the-screen) · [a session ended with an error](#a-session-shows-an-error-card)
- App and service: [Queued](#a-new-agent-says-queued) · [New Version Ready](#the-top-bar-says-new-version-ready) · [Disconnected](#the-window-says-disconnected) · [Bring Sessions Back?](#after-a-restart-enterm-asks-bring-sessions-back) · [Mac notifications](#mac-notifications-do-not-appear)
- Git: [worktree errors](#a-worktree-does-not-open) · [race does not start](#a-race-does-not-start) · [merge refused](#pick-winner-is-refused-or-the-merge-fails) · [race never finishes](#a-racer-never-finishes)
- Agents and tools: [MCP tool errors](#mcp-tools-fail) · [Safari for agents](#agents-cannot-use-safari) · [empty timeline](#the-timeline-is-empty)
- Phone: [pairing fails](#pairing-fails) · [cannot reach the computer](#the-phone-says-cant-reach-the-computer) · [computer didn't respond](#the-phone-says-computer-didnt-respond) · [no phone notifications](#phone-notifications-do-not-arrive)
- [Collecting information for a bug report](#collecting-information-for-a-bug-report)

---

## Programs

### A program is not installed or not on PATH

**What you see.** Starting an agent shows an install card instead of a box, or a card at the bottom of the terminal after the shell said "command not found". In the session picker and on the race setup page the program is marked **Not Installed**, **Opens from Outside PATH** or **Opens from the ChatGPT App**.

**Why.** Enterm asks your login shell (`$SHELL -ilc 'command -v …'`, with a 6-second timeout) which programs it can start, because the app's own `PATH` is not your terminal's. When a program is missing it also looks in the usual install locations (`~/.local/bin/<command>`, and for Codex the copy inside `/Applications/ChatGPT.app`).

| Card | Meaning | **Primary button** runs |
| --- | --- | --- |
| *<Program> Is Not Installed on This Mac* | Not found anywhere | The vendor's official install command, shown first, visibly in this terminal |
| *<Program> Is Installed but Not in PATH* | Found in `~/.local/bin` | `PATH='<folder>':"$PATH" <command>`, for this one command only |
| *Codex Found Inside the ChatGPT App* | Found in the ChatGPT app bundle | Same, with that folder |

**Fix.** Press the button, or install the program yourself and open a new terminal. To fix `PATH` permanently, add the folder in your own shell configuration; Enterm never edits it. The install commands Enterm offers are in `ToolPresence.installCommand` (`Sources/EntermCore/Sessions.swift`).

### `gemini` is not found

**What you see.** A card titled **agy Runs on a Personal Google Account**: "For personal accounts the official program is Antigravity (agy). gemini keeps working with an enterprise license or a paid API key."

**Why.** When the shell reports `gemini` as not found, Enterm points to Antigravity (`agy`), the program it treats as Google's official CLI for personal accounts.

**Fix.** Press **Run agy**, or install the Gemini CLI if you use it with an enterprise license or API key.

### A box says Status Unknown or stays on Starting

**Why.** A box opened for a program waits for the shell integration's launch event. Without it the status moves from **Starting** to **Status Unknown** after 30 seconds. Common causes:

- **An alias with the program's name.** In zsh the integration does not define its wrapper function when an alias called `claude`, `codex`, … exists, so the alias runs the program without Enterm's arguments.
- **A shell other than zsh or bash.** Other shells start without the integration ([faq](faq.md#which-shells-are-supported)).

**Fix.** Remove or rename the alias (or call the program through a function that runs `command <program>`), or use zsh or bash as the session shell (**Settings → Shell**). The program itself still runs normally in every case; only Enterm's status and approvals are missing.

### Claude Code shows Needs Approval right after starting

**Why.** Claude Code first asks whether you trust the folder, and its hooks only run after that, so Enterm reads the question from the screen (the word "trust" while starting) and marks the box **Needs Approval**.

**Fix.** Answer the question in the terminal. The status updates on the next hook event.

### Codex Status Needs Your Approval

**What you see.** In the session details: **Codex Status Needs Your Approval**. "Without this approval, the 'needs approval' state does not appear and 'done' arrives only at the end of a turn. Codex still runs."

**Why.** Enterm passes its hooks to Codex with `-c hooks.<Event>=…` on the command line. Codex asks you to trust hooks in its own `/hooks` screen and does not run them until you do. Until then Enterm only gets Codex's end-of-turn `notify`, so it cannot show approvals, route them to your phone, read the transcript for the chat view and timeline, or reliably detect a race finish.

**Fix.** Press **/hooks** in the details panel (it types `/hooks` into the session), or type it yourself, and trust Enterm's hooks. Codex asks again if the hook definition changes; the hook command contains the path of Enterm's `enterm` command, so moving the app changes it.

### Antigravity Status Needs Your Approval

**Why.** Antigravity reads hooks only from files, and Enterm does not write into your folders without asking.

**Fix.** In the session details press **Write to This Folder**. Enterm writes `.agents/hooks.json` in the project (hooks `Stop` and `PreInvocation` calling `enterm hook agy`) and remembers the file so uninstalling removes it. The file is yours to delete. Without it, Antigravity's status is read from its output.

Antigravity also prints a notice about its terms the first time you start `agy` in a folder and waits for Enter; any other key and Enter cancels. This is asked once per folder.

### Claude Code shows no status, limits or approvals

**Why.** `enterm wrap` adds `--settings` and `--mcp-config` only if you did not pass those flags yourself, and adds nothing at all if the arguments include `--help`, `-h`, `--version`, `-v`, `update`, `install`, `doctor`, `mcp`, `auth`, `login` or `logout`. A session started with your own `--settings` file therefore has no Enterm hooks, no status line and no MCP bridge.

**Fix.** Start Claude Code without `--settings` / `--mcp-config` inside Enterm, or put the settings you need in Claude Code's normal settings files. Your own status line keeps working on top of Enterm's: Enterm reads its command from your Claude settings and runs it after its own (`ENTERM_USER_STATUSLINE`).

### Gemini status comes only from the screen

**Why.** Enterm attaches its hooks and MCP server to Gemini through `GEMINI_CLI_SYSTEM_SETTINGS_PATH`. It does this only when that variable is not already set and `/Library/Application Support/GeminiCli/settings.json` does not exist, so an administrator's system settings stay in charge.

**Fix.** Nothing is broken: Gemini runs normally and its status is read from its output (writing = working, three quiet seconds = waiting). The same applies to opencode when you have set `OPENCODE_CONFIG_DIR` or `OPENCODE_CONFIG_CONTENT` yourself.

### A session shows an error card

When Claude Code's `StopFailure` hook reports an API error, the box shows the reason and one line of advice (`SessionFailure` in `Sources/EntermCore/Sessions.swift`). The card goes away once the session moves on.

| Error kind | Title | Advice |
| --- | --- | --- |
| `overloaded`, `server_error` | Server Busy / Server Error | Temporary. Send the same message again in a bit. |
| `authentication_failed` | Invalid Sign-In | Sign in again with `/login` in the session. |
| `billing_error`, `account_on_hold` | Payment Issue / Account Suspended | Check the account's billing and status page. |
| `model_not_found` | Model Not Found | Pick another model with `/model`. |
| `max_output_tokens` | Reply Hit the Limit | Type "continue" to pick up where it left off. |
| `oauth_org_not_allowed`, `invalid_request`, `cloud_credential_error`, others | Organization Doesn't Allow It / Request Denied / Couldn't Read Cloud Credentials / Unknown Error | Send the message again. If it persists, see details. |

A `rate_limit` error is shown as **Limit Reached** instead, with options to continue with another account, wait for the reset, and so on.

## App and service

### A new agent says Queued

**Why.** The power limit (**Settings → Power Limit**) queues a new agent instead of slowing everything down when one of these holds:

| Reason shown | Condition |
| --- | --- |
| Up To N Sessions at Once | The number of running agents reached the session limit (automatic: half your memory in GB, at least 2) |
| CPU Up To N% | Total CPU use is at or above the chosen share |
| Memory Pressure Critical | macOS reports critical memory pressure |
| Memory Pressure | Warning-level pressure and at least one agent already running |

The CPU and memory checks are skipped when the share is set to unlimited. Plain terminals are never queued.

**Fix.** Wait (the queued agent starts by itself when there is room and does not use any limit while waiting), press **Start Anyway**, or raise the limit. The top bar shows **◷ Queued N**.

### The top bar says New Version Ready

**Why.** You updated Enterm while sessions were running. The running `entermd` is the old build (its build stamp differs from the bundled one); it keeps serving your sessions until they end. With no open sessions the app restarts the service by itself and you never see this.

**Fix.** Press it and confirm **Switch**: the service restarts, open sessions close, and **Resume All** brings agent conversations back with each program's resume option. Or keep working and let the old service retire when its sessions end.

### The window says Disconnected

**Why.** The app lost its socket connection to `entermd` (`■ Disconnected` in the top bar). It retries every 2 seconds and starts the service again if needed.

**Fix.** Usually none. If it persists, check that `Enterm.app/Contents/MacOS/entermd` exists and that `/tmp/enterm-<uid>/` is writable by you; a stale socket file is replaced when the service starts.

### After a restart Enterm asks Bring Sessions Back?

This is expected: the pseudo terminals end with a reboot or logout. **Resume** restarts an agent with its conversation (`--resume`, `resume`, `--conversation`); the first message uses your limit as usual. A terminal reopens with its saved output. A row marked **✕ Folder Not Found** cannot be restored because its folder is gone.

### Mac notifications do not appear

**Checks, in order:**

1. **Settings → Notifications → System Notifications** is on (default). Notifications about sessions (approval needed, work done, limit reached, race over) are only posted while Enterm is not the active app; `enterm notify` messages are always posted.
2. macOS permission. The first notification asks for it; if it was denied, Enterm shows "No Notification Permission · System Settings › Notifications › Enterm". Allow it there.
3. **Signature.** macOS refuses notifications to an ad-hoc signed app. Release builds are signed with a Developer ID; `scripts/bundle.sh release` signs with a Developer ID only if one is found in your Keychain, and debug builds are always ad-hoc. A build from source without a Developer ID therefore shows no notifications; this is a macOS rule, not a bug.

## Git, worktrees and races

### A worktree does not open

| Message | Cause | Fix |
| --- | --- | --- |
| This Folder Isn't a Git Repo | The focused session's folder is not in a repository | Focus a box inside the repository |
| Worktree Opens Only for Projects on This Computer | The focused session is a remote (SSH) project | Use a local clone |
| Worktree Didn't Open: … | `git worktree add` failed; the first 120 characters of git's output follow. Typical: the branch already exists, or the target folder `<repo>.worktrees/<branch>` exists | Choose another branch name, or remove the old worktree with `git worktree remove` |
| Branch name is empty or invalid (from `worktree_ac`) | Agents may use only letters, digits, `.`, `_`, `-`, `/` | Use a simpler name |

### A race does not start

| Message | Fix |
| --- | --- |
| Write the task. | Enter a task. |
| Choose at least two programs to race. | Pick two or three of Claude Code, Codex, Gemini. At least two must be installed; the page links to **See Programs**. |
| This folder is not a git repository. | Focus a box inside the repository before opening **Start a Race**. |
| The repository has no commits yet. A race starts from a commit. | Make a first commit. |
| Couldn't open worktree: … | git's message follows. Worktrees already created for this race are removed again. |

### Pick Winner is refused or the merge fails

**"The main folder has uncommitted changes. Commit or stash them first."** The merge happens in your main working folder, and Enterm refuses to merge over tracked files with uncommitted changes (`git status --porcelain --untracked-files=no` must be empty). Untracked files do not block it. Commit or stash, then pick again. The race stays open meanwhile.

**"Couldn't merge: …"** `git merge --no-ff` failed, usually on a conflict. Enterm runs `git merge --abort`, so your main folder is as it was, and keeps the race and its worktrees. Resolve it yourself (for example merge the race branch by hand), then drop the race to clean up.

See [race.md](race.md#picking-a-winner-merge) for the exact steps.

### A racer never finishes

A racer finishes the first time it goes from **Running** to **Idle** with at least one changed file ([race.md](race.md#how-a-finish-is-detected)). It does not finish when:

- it stopped without changing any file (it may be asking you something: look at its box);
- it is waiting for an approval;
- it is Codex and its hooks are not trusted ([above](#codex-status-needs-your-approval));
- it is still **Queued** by the power limit (its clock has not started).

You can still compare and pick a winner at any time from **Race Results**; finishing order is only informative.

## Agents and tools

### MCP tools fail

| Result | Cause |
| --- | --- |
| "Bu oturum Enterm'de bulunamadı." (session not found in Enterm) | The agent was not started by Enterm, or its session ended |
| "Enterm penceresi açık değil." (the Enterm window is not open) | Browser and canvas tools need the window |
| "Enterm yanıt vermedi." / "Tarayıcı yanıt vermedi." (no answer) | The window did not answer within 30 s (canvas) or 40 s (browser) |
| "İzin verilmedi. …" (not permitted) | **Assigning Work to Other Agents** is Off on the caller's card, or you declined or did not answer within 590 s |
| "Bu ajana bağlantınız yok." / "'İş Verebilir' bağlantınız yok." (no link) | Draw a link from the calling box to the target; `is_ver` needs **Can Assign Work** |
| "Alt ajanlar ekibe mesaj yazamaz." (subagents cannot message the team) | Claude Code subagents may only call `ajan_listesi` |
| "The user took over the browser. Wait until they hand it back." | You have control of the browser view; hand it back |

Full reference: [mcp.md](mcp.md).

### Agents cannot use Safari

With **Settings → Browser → Let Agents Use Safari** on:

- "macOS didn't allow Enterm to control Safari. Turn it on in System Settings → Privacy → Automation." Allow Enterm to control Safari there. Press **Test** in the same settings section to trigger macOS's question.
- "Turn on Allow JavaScript from Apple Events in Safari's Develop menu." Enable the Develop menu in Safari's settings, then that option.
- "Sayfa izin verilen siteden çıktı" (the page left the allowed site): a click navigated to another site. Open it with `tarayici_ac` so you are asked.
- Screenshots are not available in Safari mode; agents should read the page instead.

### The timeline is empty

"This session has no transcript, or it's empty. The timeline works for Claude Code and Codex sessions." The timeline reads the CLI's own transcript, whose path Enterm learns from hook events. Other programs have no timeline; for Codex, trust the hooks; for an old race, the transcript file may have been deleted by the CLI. See [timeline.md](timeline.md#supported-programs).

## Phone

### Pairing fails

| Message | Cause | Fix |
| --- | --- | --- |
| Code Expired. Get a New Code. (Mac) | A code is valid for 5 minutes | Press **New Code** |
| Disconnected. Get a New Code. (Mac) / Disconnected. Get a New Code on the Computer. (phone) | The relay connection closed, or the other side left after the numbers appeared | Check the relay address on the Mac (**Settings → Phone**), then try again with a new code |
| The numbers differ | Someone may be between the two devices | Cancel. Do not confirm. |
| This Isn't an Enterm Code. (phone) | The scanned link is not `enterm://pair?v=1…` with a valid key, room and `ws`/`wss` relay | Scan the code on the Mac's **Pair Phone** page, or use **Copy Code** |
| Couldn't Save the Key to This Phone. (phone) | The Keychain refused to store the pairing key, so the pairing would not survive closing the app | Try pairing again with a new code |

The **Pair Phone** button is disabled while the relay address is empty.

### The phone says Can't Reach the Computer

**Why.** The phone could not complete an encrypted connection through the relay: the Mac is off or offline, the service is not running, the phone is offline, or the relay is unreachable. The phone retries with a growing delay (up to 60 s) and shows the attempt number; **Try Now** retries at once. While disconnected, approval decisions are held and sent when the connection returns.

**Checks.**

- If it says **Computer Is Asleep**, the Mac told the phone it was going to sleep; it reconnects when the Mac wakes.
- The Mac's **Pair Phone** page shows each device as **Connected** or not.
- The Mac and the phone must use the same relay. The relay URL is stored with the pairing, so changing it in Settings later does not move existing pairings: pair again.
- For a self-hosted relay: `curl https://<host>/health` should answer `ok`, and a proxy must pass WebSocket upgrades ([phone.md](phone.md#self-hosting-the-relay)).
- If the Mac removed the device, the phone was told to unpair; pair again.

### The phone says Computer Didn't Respond

Calls that need the Mac's window (accounts, Git changes, links, races, starting programs) are forwarded to it. If the window is closed, the service opens the app in the background and waits up to 8 seconds ("Enterm Couldn't Open on the Computer" if it never connects). The phone gives up after 15 seconds with "Computer Didn't Respond". Try again; if it keeps happening, open Enterm on the Mac once.

### Phone notifications do not arrive

1. The phone must allow notifications: **Settings → Allow Notifications** in the phone app, then iOS Settings.
2. Notifications go out only for **Needs Approval**, **Limit Reached**, **Failed**, and `enterm notify`. A finished turn does not send one.
3. The relay must have an APNs key configured. Without one the live connection works but no push is sent. A self-hosted relay needs a key valid for the app's bundle ID ([phone.md](phone.md#self-hosting-the-relay)).
4. The relay accepts at most 30 push requests per pairing per minute.
5. The phone sends its push token to the Mac over the encrypted link after it connects; it must have connected at least once since notifications were allowed.

## Collecting information for a bug report

Useful facts that don't expose your data:

- Enterm version (**Settings → About**) and macOS version.
- The program and its version (`claude --version`, `codex --version`, …).
- Your login shell (`echo $SHELL`), and whether you have an alias with the program's name (`alias claude`).
- Whether the problem appears in a fresh session started from the command bar.

Do not attach `devices.json`, `accounts/`, `scrollback/` or transcripts: they can contain keys, tokens or your work. Security issues go through [SECURITY.md](../SECURITY.md), not public issues.
