# MCP Bridge Reference

Enterm gives every agent session it starts a local [Model Context Protocol](https://modelcontextprotocol.io) server named `enterm`. Through it an agent can talk to the agents you linked it to, report its work on the board, drive Enterm's built-in browser, and open, arrange and close boxes on the canvas.

**On this page**

- [How the bridge works](#how-the-bridge-works)
- [Why the names are Turkish](#why-the-names-are-turkish)
- [Links and permissions](#links-and-permissions)
- [Tool summary](#tool-summary)
- Tools: [agents](#agents) · [board](#board) · [browser](#browser) · [canvas](#canvas)
- [Limits and timeouts](#limits-and-timeouts)
- [Calling the bridge by hand](#calling-the-bridge-by-hand)

## How the bridge works

The server is `enterm mcp` (`Sources/enterm/MCPServer.swift`): newline-delimited JSON-RPC 2.0 over stdio. It answers `initialize` (echoing the client's `protocolVersion`, default `2025-03-26`; capabilities `{"tools": {}}`; server name `enterm`), `ping`, `tools/list` and `tools/call`. Any other method returns error `-32601`.

Each program receives the server through its own documented mechanism, never through its user configuration ([architecture.md](architecture.md#how-each-agent-is-integrated)):

| Program | How the bridge is attached |
| --- | --- |
| Claude Code | `--mcp-config ~/Library/Application Support/Enterm/hooks/claude-mcp.json` |
| Codex | `-c mcp_servers.enterm.command=… -c mcp_servers.enterm.args=["mcp"]` |
| Gemini CLI | `mcpServers.enterm` in the settings layer passed as `GEMINI_CLI_SYSTEM_SETTINGS_PATH` (only when Enterm can apply that layer) |
| opencode | `mcp.enterm` in `OPENCODE_CONFIG_CONTENT` (only when you have not set that variable) |
| GitHub Copilot CLI | `--additional-mcp-config @…/hooks/copilot-mcp.json` |
| Cursor CLI | `mcp.json` inside the plugin passed with `--plugin-dir` |
| Antigravity, Grok, custom programs | Not attached |

The bridge identifies the caller by `ENTERM_SESSION_ID`, which `entermd` sets for every session. Outside an Enterm session every call fails with "Bu oturum Enterm'de bulunamadı." ("This session was not found in Enterm.").

Tool calls take one of three paths:

1. **Links and board** tools (`ajan_listesi`, `ozet_oku`, `is_ver`, `rapor_yaz`, `yorum_yaz`) run inside `enterm mcp` itself, reading the session list from `entermd` and the JSON stores in Enterm's support folder.
2. **Browser** tools (`tarayici_*`) are forwarded through `entermd` (`op: browser`) to the window, which drives its built-in browser (`BrowserCenter`) or, if enabled, Safari (`SafariBridge`).
3. **Canvas** tools (`tuval_durumu`, `kutu_ac`, `ekip_kur`, `worktree_ac`, `kutu_kapat`, `kart_ekle`, `kart_tasi`, `goster`, `duzenle`) are forwarded through `entermd` (`op: canvas`) to the window and carried out by `CanvasAgent` (`Sources/EntermApp/CanvasAgent.swift`).

Browser and canvas tools need the Enterm window. If no window is connected the service answers "Enterm penceresi açık değil." ("The Enterm window is not open.").

Every result is a single `text` content item; failures set `isError: true`. Inside Claude Code, Enterm's tools appear as `mcp__enterm__<name>`. Claude Code's own permission prompt is skipped for them (Enterm's `PermissionRequest` hook allows them), because the bridge applies its own checks below; subagents may call only `ajan_listesi`.

## Why the names are Turkish

Enterm's code is written in Turkish, and the tool and parameter names are Turkish identifiers written without diacritics (`kutu_ac` is "open box", `hedef` is "target"). They are part of the contract with agents and existing prompts, so they are kept as they are for compatibility; translating them would break every session and skill that uses them. The tool descriptions that `tools/list` returns are in English and explain each Turkish word, and the tables below give a translation for every name and accepted value. Result and error messages are currently returned in Turkish; this page quotes them with a translation.

## Links and permissions

Two independent things gate the bridge.

**Links** are lines you draw between two boxes on the canvas (stored in `links.json`). A link has a direction, an optional both-ways flag and one of two levels:

| Level | Identifier | Allows |
| --- | --- | --- |
| **Sees Summary** (Özetini Görür) | `summary` | `ajan_listesi` lists the target; `ozet_oku` reads it |
| **Can Assign Work** (İş Verebilir) | `delegate` | Everything above, plus `is_ver` |

A link never grants a permission: it only decides who may talk to whom. Only you draw links. An agent that opens a box with `kutu_ac`, `ekip_kur` or `worktree_ac` automatically gets a one-way **Can Assign Work** link to it.

**The permission card** of the calling session ([architecture.md](architecture.md#approvals-and-the-permission-card)) is consulted for:

- `is_ver`: refused if the caller's **Assigning Work to Other Agents** is **Off**.
- `kutu_ac`, `ekip_kur`, `worktree_ac`, `kutu_kapat`: sent to `entermd` as an approval in the **Assigning Work to Other Agents** category. **Allowed** goes ahead, **Off** is refused, **Ask First** shows you the request ("Wants to Open a Box: …", "Wants to Build a Team: …", "Wants to Open a Worktree: …", "Wants to Close a Box: …") and waits for your answer. On the default **Open** card (the program's own rules), these requests are always shown to you.
- `tarayici_ac` to a non-local address: sent as an approval in the **Internet** category with the host. On the **Open** card it asks unless you earlier allowed that host with "remember"; on other cards a remembered host is allowed and otherwise the card's Internet mode applies (**Ask First** in every built-in template).

If the approval is refused or not answered, the tool fails with "İzin verilmedi. Yetki kartınızda Başka Ajana İş Verme kapalı ya da kullanıcı reddetti." ("Not permitted: Assigning Work to Other Agents is off on your permission card, or the user declined.").

**Messages are not approvals.** `is_ver` records every message. If the text claims an approval ("user approved", "kullanıcı onayladı", "onay verildi", …), it is flagged, the window shows "Not Counted as Approval: <sender> Claimed an Approval", and the sender is told the target's permissions did not change.

## Tool summary

| Tool | Translation | Group | Gate |
| --- | --- | --- | --- |
| [`ajan_listesi`](#ajan_listesi) | agent list | agents | Links from you (any level) |
| [`ozet_oku`](#ozet_oku) | read summary | agents | Sees Summary link |
| [`is_ver`](#is_ver) | give work | agents | Can Assign Work link, card not Off |
| [`rapor_yaz`](#rapor_yaz) | write report | board | none |
| [`yorum_yaz`](#yorum_yaz) | write comment | board | Your session must have a board card |
| [`tarayici_ac`](#tarayici_ac) | open browser | browser | Internet approval for non-local hosts |
| [`tarayici_oku`](#tarayici_oku) | read browser | browser | none (Safari: page must be on an allowed site) |
| [`tarayici_tikla`](#tarayici_tikla) | click | browser | same as above |
| [`tarayici_yaz`](#tarayici_yaz) | type | browser | same as above |
| [`tarayici_goruntu`](#tarayici_goruntu) | screenshot | browser | none; built-in browser only |
| [`tuval_durumu`](#tuval_durumu) | canvas state | canvas | none |
| [`kutu_ac`](#kutu_ac) | open box | canvas | Assigning Work approval |
| [`ekip_kur`](#ekip_kur) | set up team | canvas | Assigning Work approval |
| [`worktree_ac`](#worktree_ac) | open worktree | canvas | Assigning Work approval |
| [`kutu_kapat`](#kutu_kapat) | close box | canvas | Assigning Work approval, and only boxes you opened |
| [`kart_ekle`](#kart_ekle) | add card | canvas | none |
| [`kart_tasi`](#kart_tasi) | move card | canvas | none; never to Done |
| [`goster`](#goster) | show | canvas | none |
| [`duzenle`](#duzenle) | arrange | canvas | none |

All parameters are declared with JSON Schema type `string`. Where a parameter takes a fixed set of values, the accepted spellings are listed.

**Addressing boxes.** Wherever a parameter names a box (`hedef`, `sonra`), it is matched case-insensitively against the box's display name, which is the name you gave it or, without one, `<Program> <number>` (for example `Claude Code 3`), or against the session ID. `tuval_durumu` prints these names.

## Agents

### `ajan_listesi`

Lists the agents this session has a link to (either level, either direction if the link is both ways), with their status.

| Parameter | Type | Required | Notes |
| --- | --- | --- | --- |
| none | | | |

Returns one line per agent, `name: status`, or "Bağlı ajan yok. Kullanıcı tuvalde bağlantı çizmeli." ("No linked agents. The user has to draw a link on the canvas.").

```json
{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "ajan_listesi", "arguments": {}}}
```

### `ozet_oku`

Reads a linked agent's status, its last activity and the latest lines of its screen.

| Parameter | Translation | Type | Required | Notes |
| --- | --- | --- | --- | --- |
| `hedef` | target | string | yes | Box name or session ID |

Requires a link of either level from the caller to the target. Returns `Durum` (status), `Son Etkinlik` (last activity) and the last 40 lines of plain text (escape sequences removed) from the last 16 KiB of the target's output.

```json
{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "ozet_oku", "arguments": {"hedef": "Tests"}}}
```

### `is_ver`

Sends work or a message to a linked agent by typing it into the target's terminal.

| Parameter | Translation | Type | Required | Notes |
| --- | --- | --- | --- | --- |
| `hedef` | target | string | yes | Box name or session ID |
| `mesaj` | message | string | yes | Newlines are replaced with spaces |

Requires a **Can Assign Work** link and a caller card whose **Assigning Work to Other Agents** is not **Off**. The text is written to the target's PTY as `[Ajan Mesajı, <sender>] <message>` followed by Enter, and appended to Enterm's message log (`mail/`). The target acts under its own permission card. Returns "Mesaj iletildi." ("Message delivered."), plus a warning when the text claims an approval.

```json
{"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "is_ver", "arguments": {"hedef": "Tests", "mesaj": "Add a test for the coupon refund edge case."}}}
```

## Board

### `rapor_yaz`

Writes a four-part report and moves this session's board card to **In Review** (Kontrolde). A report never marks a card **Done**.

| Parameter | Translation | Type | Required |
| --- | --- | --- | --- |
| `ne_degisti` | what changed | string | yes |
| `ne_denendi` | what was tested | string | yes |
| `ne_denenmedi` | what was not tested | string | yes |
| `ne_bekliyor` | what is pending | string | yes |

The report is written as Markdown to `<folder>/ekip/raporlar/<yyyy-MM-dd-HHmm>-<author>.md`, where `<folder>` is the team's folder if a team is set up, otherwise the session's working folder. It is also stored in `team.json`, and the session's open card (if any) gets the report and moves to **In Review**. Returns "Rapor yazıldı: <path>" ("Report written: <path>").

```json
{"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "rapor_yaz", "arguments": {
  "ne_degisti": "Password reset form and endpoint",
  "ne_denendi": "Unit tests for the token expiry",
  "ne_denenmedi": "Email delivery",
  "ne_bekliyor": "Copy review"}}}
```

### `yorum_yaz`

Adds a comment to this session's board card. An agent's comment does not count as approval.

| Parameter | Translation | Type | Required |
| --- | --- | --- | --- |
| `metin` | text | string | yes |

Fails with "Bu oturumun pano kartı yok." ("This session has no board card.") if no card is assigned to the session.

```json
{"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "yorum_yaz", "arguments": {"metin": "Blocked on the API key for staging."}}}
```

## Browser

The browser tools drive the browser view in the Enterm window (a `WKWebView`). With **Settings → Browser → Let Agents Use Safari** on, they drive a Safari window of their own instead; macOS asks for Automation permission, and Safari's "Allow JavaScript from Apple Events" must be enabled. While you have taken control of the browser, every browser tool fails with "The user took over the browser. Wait until they hand it back."

### `tarayici_ac`

Opens a URL and returns the page.

| Parameter | Translation | Type | Required | Notes |
| --- | --- | --- | --- | --- |
| `adres` | address | string | yes | `http` or `https` URL |

`localhost`, `127.0.0.1`, `::1`, `*.localhost` and `*.test` need no approval; any other host goes through the **Internet** approval described above. Returns the page title, URL and up to 8,000 characters of the page's visible text (`document.body.innerText`). In Safari mode, opening a site adds it (its last two host labels, so `accounts.example.com` counts as `example.com`) to the sites the other Safari tools may act on.

```json
{"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {"name": "tarayici_ac", "arguments": {"adres": "http://localhost:3000/login"}}}
```

### `tarayici_oku`

Returns the open page's title, URL and up to 8,000 characters of text. No parameters. In Safari mode it fails if the page has left the allowed sites: "Sayfa izin verilen siteden çıktı" ("The page left the allowed site"); open it again with `tarayici_ac` to be asked.

```json
{"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": "tarayici_oku", "arguments": {}}}
```

### `tarayici_tikla`

Clicks an element.

| Parameter | Translation | Type | Required | Notes |
| --- | --- | --- | --- | --- |
| `hedef` | target | string | yes | CSS selector or visible text |

The value is tried as a CSS selector first. Otherwise Enterm looks among `a`, `button`, `input[type=submit]`, `input[type=button]`, `[role=button]`, `label` and `summary` for an element whose text (or value) equals it, then for one that contains it. Returns "Tıklandı: <text>" ("Clicked: …", up to 80 characters) or fails with "Öğe bulunamadı" ("Element not found").

```json
{"jsonrpc": "2.0", "id": 8, "method": "tools/call", "params": {"name": "tarayici_tikla", "arguments": {"hedef": "Sign in"}}}
```

### `tarayici_yaz`

Types text into a field.

| Parameter | Translation | Type | Required | Notes |
| --- | --- | --- | --- | --- |
| `hedef` | target | string | yes | CSS selector, or an `input`/`textarea`'s `name`, `placeholder`, `id` or `aria-label` |
| `metin` | text | string | yes | Replaces the field's value |

The value is set through the element's native setter and `input` and `change` events are dispatched, so frameworks that track input see it. Returns "Yazıldı" ("Typed") or fails with "Alan bulunamadı" ("Field not found").

```json
{"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": {"name": "tarayici_yaz", "arguments": {"hedef": "email", "metin": "dev@example.com"}}}
```

### `tarayici_goruntu`

Saves a PNG screenshot of the built-in browser and returns its path, `~/Library/Application Support/Enterm/browser-shots/<unix-time>.png`. No parameters. Not available in Safari mode ("Safari'de ekran görüntüsü için ayrı izin gerekir", "a screenshot in Safari needs a separate permission").

```json
{"jsonrpc": "2.0", "id": 10, "method": "tools/call", "params": {"name": "tarayici_goruntu", "arguments": {}}}
```

## Canvas

### `tuval_durumu`

Lists everything on the canvas. No parameters.

One line per box: name · program · status · project · folder, followed where known by `siz` (you), `sizin açtığınız` (opened by you), `bağlam %N` (context used), `başlık:` (the program's own title), `döngü:` (a Claude Code loop) and `port` (listening ports). Then the views (`Görünümler`), a board summary per column (`Pano`), and the number of boxes queued with `sonra`.

```json
{"jsonrpc": "2.0", "id": 11, "method": "tools/call", "params": {"name": "tuval_durumu", "arguments": {}}}
```

### `kutu_ac`

Opens a new agent or terminal box and links you to it with **Can Assign Work**.

| Parameter | Translation | Type | Required | Accepted values / default |
| --- | --- | --- | --- | --- |
| `program` | program | string | no | `claude` (or `claude code`), `codex`, `agy` (or `antigravity`), `gemini`, `opencode`, `grok`, `copilot` (or `github copilot`), `cursor` (or `cursor-agent`), `terminal` (or `kabuk`). Default and fallback for an unrecognized value: `claude` |
| `ad` | name | string | no | Box name. Default: the program's name. A taken name gets ` 2`, ` 3`, … |
| `klasor` | folder | string | no | Working folder, `~` allowed. Default: the caller's folder. Must exist |
| `gorev` | task | string | no | First message, passed to the program as its start argument (ignored for `terminal`) |
| `sonra` | after | string | no | Name of a box to wait for: this box opens only when that one finishes its turn |

Requires the **Assigning Work to Other Agents** approval. The program must be installed and the [power limit](architecture.md#resource-use-and-the-motion-rule) may queue it. With `sonra`, the box opens when the named session goes from **Running** or **Needs Approval** to **Idle**, **Exited** or **Failed**; the wait is held in the window's memory and does not survive quitting the app. Returns "Açılıyor: <name> (<program>, <folder>)" ("Opening: …").

```json
{"jsonrpc": "2.0", "id": 12, "method": "tools/call", "params": {"name": "kutu_ac", "arguments": {
  "program": "codex", "ad": "Tests", "gorev": "Write tests for src/coupon.ts", "sonra": "Claude Code 1"}}}
```

### `ekip_kur`

Opens several agents at once, groups them with you and opens a board card for each.

| Parameter | Translation | Type | Required | Notes |
| --- | --- | --- | --- | --- |
| `uyeler` | members | string | yes | `name: program: task` per member, separated by `;` or newlines. `program` defaults to `claude`; the task is optional. At most 6 members |
| `ad` | name | string | no | Team (group) name. Default `Ekip` |
| `klasor` | folder | string | no | Working folder for all members. Default: the caller's folder |
| `kart` | card | string | no | `hayir` ("no") to skip creating board cards |

Requires the **Assigning Work to Other Agents** approval. A new group is created with the caller in it, and each member opens as with `kutu_ac`. For each member that has a task, a card titled with the task is created in **In Progress** and assigned to that member, unless `kart` is `hayir`. If one member fails to open, the call stops and reports which members did open.

```json
{"jsonrpc": "2.0", "id": 13, "method": "tools/call", "params": {"name": "ekip_kur", "arguments": {
  "ad": "Checkout", "uyeler": "UI: claude: build the payment form; Tests: codex: write the e2e tests"}}}
```

### `worktree_ac`

Creates a git worktree on a new branch next to the project, starts an agent in it and groups it, so two agents do not write to the same files.

| Parameter | Translation | Type | Required | Notes |
| --- | --- | --- | --- | --- |
| `dal` | branch | string | yes | Letters, digits, `.`, `_`, `-` and `/` only |
| `program` | program | string | no | As in `kutu_ac`. Default `claude` |
| `ad` | name | string | no | Box name. Default: the branch name |
| `gorev` | task | string | no | First message |

Requires the **Assigning Work to Other Agents** approval. Enterm runs `git worktree add <folder> -b <dal>` in the repository of the box that is **focused in the window** (not necessarily the caller's), so the branch starts from that repository's current `HEAD`. The folder is `<parent>/<repo>.worktrees/<dal with "/" replaced by "-">`. It fails for a remote (SSH) project, outside a git repository, or when git refuses (for example an existing branch name).

```json
{"jsonrpc": "2.0", "id": 14, "method": "tools/call", "params": {"name": "worktree_ac", "arguments": {
  "dal": "feature/reset-password", "program": "claude", "gorev": "Add password reset to the login page"}}}
```

### `kutu_kapat`

Closes a box.

| Parameter | Translation | Type | Required |
| --- | --- | --- | --- |
| `hedef` | target | string | yes |

Requires the **Assigning Work to Other Agents** approval, and works only on boxes the caller opened ("Yalnız kendi açtığınız kutuyu kapatabilirsiniz", "You can only close boxes you opened"). You close the others.

```json
{"jsonrpc": "2.0", "id": 15, "method": "tools/call", "params": {"name": "kutu_kapat", "arguments": {"hedef": "Tests"}}}
```

### `kart_ekle`

Adds a card to the board (column **To Do**), optionally assigned to a box.

| Parameter | Translation | Type | Required | Accepted values |
| --- | --- | --- | --- | --- |
| `baslik` | title | string | yes | Must not be empty |
| `aciklama` | description | string | no | Details |
| `hedef` | target | string | no | Box to assign; an unknown name leaves the card unassigned |
| `oncelik` | priority | string | no | `yuksek` (high) or empty |

Returns "Kart eklendi: <title> (kimlik <first 8 characters of the ID>)" ("Card added: … (ID …)").

```json
{"jsonrpc": "2.0", "id": 16, "method": "tools/call", "params": {"name": "kart_ekle", "arguments": {
  "baslik": "Fix the refund rounding", "hedef": "Tests", "oncelik": "yuksek"}}}
```

### `kart_tasi`

Moves a board card to another column.

| Parameter | Translation | Type | Required | Accepted values |
| --- | --- | --- | --- | --- |
| `kart` | card | string | yes | The card's exact title (case-insensitive), or at least the first 4 characters of its ID |
| `sutun` | column | string | yes | `yapilacak` / `yapılacak` / `todo` (To Do), `suruyor` / `sürüyor` / `doing` (In Progress), `kontrolde` / `review` (In Review), `karar` / `karar bekliyor` / `decision` (Awaiting Decision) |

Only you move a card to **Done**. Moving a card to **In Progress** sends it to its assigned agent: the agent's terminal receives `Pano Kartı: <title>. <details> Bitince rapor_yaz aracıyla raporla.` ("Board card: … When done, report with the rapor_yaz tool."). An unassigned card, or one assigned to a plain terminal, is not sent.

```json
{"jsonrpc": "2.0", "id": 17, "method": "tools/call", "params": {"name": "kart_tasi", "arguments": {"kart": "Fix the refund rounding", "sutun": "suruyor"}}}
```

### `goster`

Puts something on the canvas as a view.

| Parameter | Translation | Type | Required | Accepted values |
| --- | --- | --- | --- | --- |
| `tur` | kind | string | yes | `not` (note), `web` (web page), `gorsel` (image), `video` |
| `icerik` | content | string | yes | Note text; an `http`/`https` URL for `web`; an existing file path for `gorsel` and `video` (`~` allowed) |

An image is shown in a web view of its `file://` URL.

```json
{"jsonrpc": "2.0", "id": 18, "method": "tools/call", "params": {"name": "goster", "arguments": {"tur": "web", "icerik": "http://localhost:5173"}}}
```

### `duzenle`

Arranges the canvas.

| Parameter | Translation | Type | Required | Accepted values |
| --- | --- | --- | --- | --- |
| `islem` | action | string | yes | `diz` (line the boxes up), `sigdir` (fit all of them in view) |

```json
{"jsonrpc": "2.0", "id": 19, "method": "tools/call", "params": {"name": "duzenle", "arguments": {"islem": "sigdir"}}}
```

Every canvas action that changes something also shows a line in the window's status hint, so you always see what an agent did ("<agent> Opened a Box: …", "<agent> Added a Card to the Board", …).

## Limits and timeouts

| Limit | Value | Where |
| --- | --- | --- |
| Wait for an approval | 590 s | `MCPServer.allowed`, `MCPServer.browser` |
| Canvas tool reply | 30 s, then "Enterm yanıt vermedi." | `MCPServer.canvas` |
| Browser tool reply | 40 s, then "Tarayıcı yanıt vermedi." | `MCPServer.browser` |
| Session list and `tail` requests | 2 s | `MCPServer.sessions`, `ozet_oku` |
| Page text returned | 8,000 characters | `BrowserCenter.readScript` |
| Screen text in `ozet_oku` | last 40 lines of the last 16 KiB | `Service.plainText` |
| Team size in `ekip_kur` | 6 members | `CanvasAgent.team` |
| Click result text | 80 characters | `BrowserCenter.clickScript` |

## Calling the bridge by hand

From a terminal inside an Enterm session (so `ENTERM_SESSION_ID` is set), you can talk to the bridge directly:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"tuval_durumu","arguments":{}}}' \
  | "$ENTERM_CLI" mcp
```

Each request gets one JSON line back. Requests without an `id` (notifications) are ignored.
