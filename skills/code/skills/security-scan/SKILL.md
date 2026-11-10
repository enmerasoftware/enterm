---
name: security-scan
description: Scan a codebase or a change for common security problems: secrets, injection, unsafe deserialisation, weak crypto, permissive CORS, vulnerable dependencies. Use when the user asks for a security review or audit.
---

# Security scan

1. Scope: the whole repo, or `git diff origin/<base>...HEAD` for a change. Say which.
2. Secrets: search for keys and tokens (`AKIA`, `sk-`, `ghp_`, `-----BEGIN`, `password =`, `.env` committed). Never print a full secret; show the first 4 characters.
3. Input handling: SQL built with string concatenation, shell commands with user input, path joins with user input, template rendering without escaping, `eval`.
4. Auth: endpoints without checks, IDs taken from the request without ownership checks, sessions without expiry.
5. Dependencies: run the ecosystem's audit if available (`npm audit --omit=dev`, `pip-audit`, `cargo audit`, `composer audit`, `bundle audit`) and summarise high and critical only.
6. Each finding: file:line, how it is exploited in one sentence, severity, fix. Mark guesses as guesses.
