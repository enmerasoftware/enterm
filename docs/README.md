# Enterm Documentation

Technical documentation for Enterm, the native macOS canvas for AI coding agents. For an overview, installation and building from source, start with the [project README](../README.md).

| Page | What it covers |
| --- | --- |
| [Architecture](architecture.md) | The processes (`EntermApp`, `entermd`, `enterm`), the Unix socket and Wire protocol, how each agent CLI is integrated without touching your config, approvals, environment variables, state files, the motion rule and localization. |
| [MCP bridge reference](mcp.md) | Every tool of the local MCP server agents use to work the canvas: parameters, accepted values, link and permission gating, limits and example calls. |
| [iPhone companion](phone.md) | Pairing (QR, X25519, six-digit check), per-connection encryption, what the relay can and cannot see, sealed notifications, Face ID approvals, app lock, Live Activity and self-hosting the relay. |
| [Race](race.md) | One task for several agents in separate worktrees: branch naming, the prompt, finish detection, stats, tests, merging the winner, dropping, phone control and limitations. |
| [Timeline](timeline.md) | The replay of what an agent did: transcript parsing, event kinds, gap compression, playback and what the HTML export contains. |
| [Library](library.md) | Shared prompts, race tasks and skill packs: browsing, running, racing, reviewing and adding packs, sharing, safety and files. |
| [Design check](design-check.md) | ai-design-check on the focused project: findings, mechanical fixes, running-page scan, fixing with an agent, design races, the fix skill. |
| [FAQ](faq.md) | Short answers about config files, tokens, supported agents, quitting, privacy, SSH, power use, languages and uninstalling. |
| [Troubleshooting](troubleshooting.md) | Failure modes Enterm detects and how to fix them: missing programs, hooks that need trust, the service, notifications, worktrees, races, MCP tools and the phone. |
| [Maintainer notes](MAINTAINERS.md) | Internals, test driver, phone and release process, in Turkish. |

Other project documents: [CONTRIBUTING.md](../CONTRIBUTING.md) (setup, ground rules, on-screen text), [SECURITY.md](../SECURITY.md) (reporting vulnerabilities), [relay/README.md](../relay/README.md) (relay server, Turkish), [skills/README.md](../skills/README.md) (skill packs).
