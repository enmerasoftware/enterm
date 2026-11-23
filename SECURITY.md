# Security Policy

Enterm starts programs in your terminal, relays their approval questions and can pair with a phone over a
relay server. A security bug in any of those parts matters, and we would rather hear about it privately first.

## Supported versions

Enterm updates itself through Sparkle, so fixes go into the latest release only.

| Version | Supported |
| ------- | --------- |
| 0.1.x (latest release) | Yes |
| Anything older | No, please update first |

## Reporting a vulnerability

**Please do not open a public issue, discussion or pull request for a vulnerability.**

Use GitHub's private vulnerability reporting instead:

1. Open the [Security tab](https://github.com/enmerasoftware/enterm/security) of this repository.
2. Choose **Report a vulnerability**
   ([direct link](https://github.com/enmerasoftware/enterm/security/advisories/new)).
3. Fill in the form. Only you and the maintainers can see the report.

### What to include

- What an attacker can do, and what they need first (local access, a paired phone, control of the relay,
  a malicious repository or transcript, and so on).
- Steps to reproduce, ideally the smallest ones that still show the problem.
- The Enterm version (Settings → About), the macOS version and, if the phone is involved, the iOS version.
- Which part is affected (see the scope below) and the agent CLI the session ran, if any.
- A proof of concept, logs or screenshots, with secrets and personal data removed.
- Whether and how you would like to be credited.

### What to expect

Enterm is maintained by a small team, so these are goals, not guarantees:

- An acknowledgement within **5 working days**.
- A first assessment (confirmed, needs more information, or not a vulnerability) within **14 days**.
- For confirmed issues, a fix in a new release as soon as we can, with the severity guiding the order. We
  will keep you informed in the advisory thread.
- Coordinated disclosure: we publish a GitHub security advisory once a fixed release is out, and credit you
  in it and in the release notes if you want. Please give us a reasonable chance to ship a fix before
  disclosing publicly.

## Scope

In scope, everything in this repository:

- **The Mac app** (`Sources/EntermApp`): the canvas, terminals, permission templates and approval cards,
  the built-in browser and Safari control, `enterm://` link handling, and the updater.
- **The session service `entermd`** (`Sources/entermd`): owns the pseudo terminals, the local socket and
  phone pairing.
- **The `enterm` command and its MCP bridge** (`Sources/enterm`): the hooks the agent CLIs call and the
  tools agents use to talk to each other and to the canvas.
- **The shared core** (`Sources/EntermCore`): pairing, encryption, permissions and link rules.
- **The iPhone app** (`enterm-ios/`), including its notification and widget extensions.
- **The relay server** (`relay/`).
- **The preset skill packs** (`skills/`), for example a skill that tells an agent to run something unsafe.

Out of scope:

- **The agent CLIs themselves**: Claude Code, Codex, Gemini, opencode, Copilot, Cursor, Grok, Antigravity
  and any program you add. Enterm runs them unchanged; please report their bugs to their vendors. A way to
  use Enterm to make one of them do something it otherwise would not *is* in scope.
- What an agent does with permissions you granted it, such as running a command you approved.
- Attacks that need an already compromised user account or Mac (for example, an attacker who can already
  read your files or attach a debugger).
- Third-party dependencies (SwiftTerm, Sparkle, whisper.cpp), unless Enterm uses them in an unsafe way.
  Please report their own bugs upstream.
- Missing hardening without a demonstrated impact, and social engineering of the maintainers.

## Security model in short

- **Hands off your configuration.** Enterm never edits `.zshrc`, `~/.claude`, `~/.codex` or any other
  configuration file. It integrates through launch arguments and environment variables only.
- **No tokens.** Your subscription or API credentials stay with the official programs. A separate account
  is kept by the program itself, through `CLAUDE_CONFIG_DIR` or `CODEX_HOME`; Enterm never reads or stores
  the token.
- **Permissions and approvals.** With the default Open template a program runs with its own rules, as in a plain terminal, and
  its questions reach you right away. Stricter permission templates (Read Only, Development, Admin, Server
  Maintenance) let Enterm decide through its approval card. Tools that let an agent open boxes or hand work
  to another agent need the matching permission, and an agent can only close the boxes it opened.
- **End-to-end phone pairing.** The QR code carries an ephemeral public key. The Mac and the phone derive a
  shared secret with X25519, and you confirm the pairing by comparing a six-digit number on both screens.
  Traffic is encrypted with ChaCha20-Poly1305 using keys derived with HKDF-SHA256, and every connection uses
  a fresh key.
- **The relay sees ciphertext only.** It forwards encrypted bytes and push notifications, cannot read the
  content and keeps no record of it. You can run your own relay.
- **Local storage.** Paired device keys live on the Mac in `devices.json` with `0600` permissions, and in
  the Keychain on the phone.
- **Signed releases.** The Mac app is signed with a Developer ID and notarized by Apple. Updates are
  delivered through Sparkle, and each update is checked against an EdDSA signature before it installs.

More detail: [docs/architecture.md](docs/architecture.md) and [docs/phone.md](docs/phone.md).
