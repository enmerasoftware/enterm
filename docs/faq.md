# Frequently Asked Questions

Short, precise answers. Each one points to the page or source file with the details.

**Questions**

1. [Does Enterm change my configuration files?](#does-enterm-change-my-configuration-files)
2. [Does Enterm see my subscription tokens or API keys?](#does-enterm-see-my-subscription-tokens-or-api-keys)
3. [Which agents does it support?](#which-agents-does-it-support)
4. [Does it modify or proxy the agent CLIs?](#does-it-modify-or-proxy-the-agent-clis)
5. [What happens when I quit the app?](#what-happens-when-i-quit-the-app)
6. [What happens when the Mac restarts or sleeps?](#what-happens-when-the-mac-restarts-or-sleeps)
7. [Who answers an agent's permission questions?](#who-answers-an-agents-permission-questions)
8. [Is the iPhone app required?](#is-the-iphone-app-required)
9. [What data leaves my Mac? Is there telemetry?](#what-data-leaves-my-mac-is-there-telemetry)
10. [Where does Enterm store its data?](#where-does-enterm-store-its-data)
11. [Can I use it with remote machines over SSH?](#can-i-use-it-with-remote-machines-over-ssh)
12. [How much CPU and memory does it use? Is there a low-power mode?](#how-much-cpu-and-memory-does-it-use-is-there-a-low-power-mode)
13. [Can I use several accounts?](#can-i-use-several-accounts)
14. [Which shells are supported?](#which-shells-are-supported)
15. [Which languages does the interface support?](#which-languages-does-the-interface-support)
16. [Can my own scripts send a notification?](#can-my-own-scripts-send-a-notification)
17. [Can agents control Enterm?](#can-agents-control-enterm)
18. [How do I uninstall Enterm?](#how-do-i-uninstall-enterm)
19. [What are the system requirements?](#what-are-the-system-requirements)

---

### Does Enterm change my configuration files?

No. Enterm does not write to `~/.zshrc`, `~/.bashrc`, `~/.claude`, `~/.codex`, `~/.gemini` or any other program's configuration. Shell integration is loaded through `ZDOTDIR` (zsh) or `--init-file` (bash) pointing at Enterm's own folder, which then sources your own files. Agent integration is passed per launch as arguments (`--settings`, `--mcp-config`, `--plugin-dir`, `-c …`) or environment variables (`GEMINI_CLI_SYSTEM_SETTINGS_PATH`, `OPENCODE_CONFIG_DIR`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME`), all pointing into `~/Library/Application Support/Enterm/`.

Some features you start do write into **project** folders: race and worktree folders next to the repository, `ekip/raporlar/` reports, `.enterm/` files for notes, whiteboard and scheduler, and, only after you press a button, `.agents/hooks.json` for Antigravity. See [architecture.md](architecture.md#files-enterm-may-write-outside-its-own-folder).

### Does Enterm see my subscription tokens or API keys?

**Subscription logins: no.** When you sign in, it is the official CLI that signs in and stores its tokens, either in its usual place or, for an extra account added in Enterm, in a directory under `~/Library/Application Support/Enterm/accounts/` that is passed as `CLAUDE_CONFIG_DIR` or `CODEX_HOME`. Enterm never reads those files.

**API keys you type into Enterm: yes, by design.** An API-key account stores the key in the macOS Keychain (service `tr.com.enmera.enterm.apikey`) and passes it as `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` to the sessions that use that account. Uninstalling removes these Keychain items.

**Model gateway:** only the *name* of the environment variable holding the key is stored; your shell expands it when the session starts. See [architecture.md](architecture.md#how-each-agent-is-integrated).

### Which agents does it support?

Claude Code (`claude`), Codex (`codex`), Antigravity (`agy`), Gemini CLI (`gemini`), opencode (`opencode`), Grok (`grok`), GitHub Copilot CLI (`copilot`) and Cursor CLI (`cursor-agent`), plus any program you add under **Settings → Custom Programs**. How deep the integration goes differs per program:

| | Claude Code | Codex | Gemini | opencode | Copilot | Cursor | Antigravity | Grok | Custom |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Status from hooks | ✓ | ✓ (after `/hooks`) | report only | report only | report only | report only | with opt-in file | | |
| Approvals in Enterm and on the phone | ✓ | ✓ (after `/hooks`) | | | | | | | |
| MCP bridge | ✓ | ✓ | ✓ (conditional) | ✓ (conditional) | ✓ | ✓ | | | |
| Chat view and timeline | ✓ | ✓ | | | | | | | |
| Usage limits on the status line | ✓ | ✓ | | | | | | | |
| Race | ✓ | ✓ | ✓ | | | | | | |

Programs without hook status are still tracked from their output (writing = working, three quiet seconds = waiting). Details in [architecture.md](architecture.md#how-each-agent-is-integrated).

### Does it modify or proxy the agent CLIs?

No. Enterm finds the program on your `PATH` and `exec`s it with extra documented arguments or variables (`Sources/enterm/main.swift`, `wrap`). It does not patch the binary, sit between the CLI and its vendor, or see the network traffic. The agents talk to their own services exactly as in a plain terminal.

### What happens when I quit the app?

The sessions keep running. They belong to the background service `entermd`, not the window. Reopening Enterm reconnects to it and shows "Enterm Reopened · Sessions Never Stopped". Paired phones keep working while the window is closed; if a phone needs something only the window can do, the service opens the app in the background.

The service exits by itself 30 seconds after no client is connected and every session has ended. With **Settings → Behavior → Ask Before Quitting** on (the default), quitting asks once.

### What happens when the Mac restarts or sleeps?

**Restart or log out:** the pseudo terminals end with the service, so running programs stop. On the next launch Enterm offers **Bring Sessions Back?**: an agent session is resumed with the program's own resume option (Claude Code `--resume`, Codex `resume`, Antigravity `--conversation`), and a terminal reopens in its folder with its last saved output (if **Keep Terminal Transcript** is on). Agents are never restarted without you pressing **Resume**.

**Sleep:** processes are suspended by macOS as usual. **Settings → Behavior → Keep Computer Awake While a Program Runs** (on by default; not for plain terminals) prevents idle system sleep while an agent works and releases it when the work ends; the setting notes that macOS may still sleep if the lid closes. A paired phone shows "Computer Asleep" instead of "No Connection".

### Who answers an agent's permission questions?

By default, the program itself, exactly as in a plain terminal: the default permission template **Open** passes everything through, and the box lights up as **Needs Approval** while the program's own question is on screen. Stricter templates (Read Only, Development, Admin, Server Maintenance) let Enterm's permission card allow, deny or ask, for Claude Code and for Codex with trusted hooks. **One-Click Approval** additionally shows Claude Code's own question under the box. Messages from other agents never count as approval. See [architecture.md](architecture.md#approvals-and-the-permission-card).

### Is the iPhone app required?

No. Everything works on the Mac alone. The phone code in the service (`PhoneCenter`) does nothing until a phone is paired; no relay connection is opened before that.

### What data leaves my Mac? Is there telemetry?

There is no analytics, crash reporting or usage tracking code in Enterm. Enterm itself connects to the network only for:

| What | When |
| --- | --- |
| Update check (Sparkle) against `github.com/enmerasoftware/enterm/releases/latest/download/appcast.xml` | Release builds only, automatically once a day and when you press **Check for Updates** |
| Dictation model download from Hugging Face (`ggerganov/whisper.cpp`) | Only when you choose to download a model |
| A program's official installer (for example `curl -fsSL https://claude.ai/install.sh \| bash`) | Only when you press **Run in This Terminal** on an install card; the command is shown first and runs visibly in the terminal |
| Web pages | Pages you, or an agent you allowed, open in the browser view |
| Model gateway discovery (`/v1/models`) | Only when you press **Find Models** |
| GitHub issues (`gh issue list`) | Only when you pull issues onto the board |
| The relay | Only after you pair a phone; all content is end-to-end encrypted ([phone.md](phone.md#what-the-relay-can-and-cannot-see)) |

The agent CLIs talk to their vendors as they always do; that traffic is theirs, not Enterm's. Antigravity's terms count usage as consent to product improvement; Enterm shows that notice once per folder before starting `agy`, and does not see or send that data.

### Where does Enterm store its data?

In `~/Library/Application Support/Enterm/` (JSON files mode `0600`, folders `0700`), API keys in the Keychain, the service socket in `/tmp/enterm-<uid>/`. Terminal output tails are stored unencrypted under `scrollback/` while **Settings → Session Protection → Keep Terminal Transcript** is on; turn it off to keep no output on disk. The full list is in [architecture.md](architecture.md#state-files).

### Can I use it with remote machines over SSH?

Yes, as remote projects. **Connect via SSH** (or **Settings → Remote Servers**) takes a host (hosts from `~/.ssh/config` are offered) and a folder. Enterm opens a terminal running `ssh -t <host> "cd <folder> && exec $SHELL -l"`, and its Files and Git screens run their commands on the server over `ssh -o BatchMode=yes`, so key-based login is required for those. Enterm does not read your keys.

On the server, Enterm's shell integration and hooks are not installed, so the install cards and agent status do not appear there. Worktrees and races work only on local repositories.

### How much CPU and memory does it use? Is there a low-power mode?

The design goal is zero work while idle: no polling timers in the service, animation only when something happens and only while the window is visible, and sampling for the power limit only while agents run. This repository does not publish benchmark numbers; `scripts/measure.sh` measures idle CPU and memory on your own Mac.

**Settings → Power Limit** has:

- **Low Power Mac:** motion and glows off, notch hidden, only the focused box drawn live (others refresh every 2 seconds).
- **Use at Most This Much of the Mac's Power** (25%, 50%, 75%, unlimited) and **Run at Most This Many Sessions at Once** (automatic: half your memory in GB, at least 2). Over a limit, a new agent waits as **Queued** instead of slowing everything down; running work never stops, plain terminals are never queued, and you can **Start Anyway**.

Per session, the service keeps 1 MiB of output in memory. See [architecture.md](architecture.md#resource-use-and-the-motion-rule).

### Can I use several accounts?

Yes, for Claude Code and Codex. **Settings → Accounts** adds a subscription account (a separate config directory; the official program shows its own sign-in in a terminal) or an API-key account. A session is started with one account; when a limit is reached, Enterm offers to continue with another. The five-hour and weekly limits Claude Code and Codex report are shown per account.

### Which shells are supported?

zsh and bash get the full integration (working directory, program detection, start commands). Other shells start as a plain login shell without it, so agent status for programs started there is not reported through the shell; the default shell can be chosen in **Settings → Shell**. Enterm detects installed programs by running your login shell (`$SHELL -ilc`), so it sees the same `PATH` as your terminal; for shells other than zsh and bash it skips that detection.

### Which languages does the interface support?

English and Turkish, on the Mac and the iPhone. By default a Mac set to Turkish shows Turkish and any other Mac shows English. **Settings → Appearance → Language** overrides it; on the Mac it takes effect after **Reopen** (sessions keep running), on the phone at once. MCP tool names and some messages agents see are Turkish identifiers ([mcp.md](mcp.md#why-the-names-are-turkish)). Adding a language: see [CONTRIBUTING.md](../CONTRIBUTING.md).

### Can my own scripts send a notification?

Yes. Inside an Enterm session:

```bash
"$ENTERM_CLI" notify "Build finished"
```

The text appears in the window and goes to paired phones as an encrypted notification. If the service is not running the command prints an error and exits with status 1. (`ENTERM_CLI` is set in every session; **Settings → Notifications → Notify from Scripts** shows the command as `enterm notify`.)

### Can agents control Enterm?

Yes, within limits you set. Every session gets a local MCP server with tools to read linked agents, send them work, write reports, use the built-in browser, and open, close and arrange boxes. Opening boxes needs the **Assigning Work to Other Agents** permission and, on the default card, your approval each time; an agent can only close boxes it opened and cannot move a board card to Done. Full reference: [mcp.md](mcp.md).

### How do I uninstall Enterm?

Use **Uninstall Enterm** from the command palette or menu (`Sources/EntermApp/Remote.swift`, `UninstallPage`). After a confirmation it:

1. Deletes the API keys you added from the Keychain.
2. Deletes the hook files it wrote into project folders (the Antigravity `.agents/hooks.json` files it recorded).
3. Tells the service to end every session and exit.
4. Deletes `~/Library/Application Support/Enterm/` (settings, account directories, output tails, board, team, messages, paired devices, races) and quits.

It leaves `~/.claude`, `~/.codex` and `~/.gemini` alone (Enterm never wrote there), and keeps the `ekip/` and `.enterm/` folders in your projects, which are yours. Then move `Enterm.app` to the Trash, or `brew uninstall --cask enterm` if you installed it with Homebrew. Race worktrees are removed when a race ends; any left from a race you never ended can be removed with `git worktree remove`.

On the phone, **Settings → Remove Computer** deletes the pairing; deleting the app removes the rest.

### What are the system requirements?

macOS 14 (Sonoma) or later (`LSMinimumSystemVersion` 14.0). The iPhone app targets iOS 17 and iPhone only. Building from source needs Xcode with Swift tools 5.10; see [README.md](../README.md#build-from-source).
