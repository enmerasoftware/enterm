---
title: Upgrade a dependency safely
summary: "Upgrade one dependency to its latest major version, read its changelog for breaking changes, adapt the code and prove nothing regressed."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [dependencies, refactor]
author: enmerasoftware
title_tr: Bir bağımlılığı güvenle yükselt
summary_tr: "Bir bağımlılığı son ana sürümüne yükseltir, kırıcı değişiklikler için sürüm notlarını okur, kodu uyarlar ve hiçbir şeyin bozulmadığını kanıtlar."
---
Upgrade a dependency of this project safely. If I did not name one, list outdated dependencies (`npm outdated`, `pip list --outdated`, `cargo outdated`, `go list -m -u all`, `bundle outdated`, and so on), and pick the one that is most behind on a major version and most used in the code; tell me which and why before you change anything.

1. Run the test suite and build first and record the result, so later failures are not blamed on the upgrade.
2. Read the dependency's changelog, release notes and migration guide for every version between the current and the target. List each breaking change and whether this project is affected, with the file and line where it uses that API.
3. Upgrade only this dependency (and peers it strictly requires). Update the lock file with the package manager, never by hand.
4. Adapt the code for each breaking change that affects the project. Prefer the replacement the migration guide recommends. Do not refactor unrelated code.
5. Verify: build, type-check, lint and run the full test suite. Then exercise the code that uses the dependency directly: run the app or a small script through the affected paths, since tests may not cover them. Check for new deprecation warnings in the output.
6. Check what changed in the dependency tree (`git diff` of the lock file): note new transitive packages and any security advisories (`npm audit`, `pip-audit`, `cargo audit`).

Report: from and to versions, the breaking changes and how each was handled, files changed, the verification commands with their results, new warnings, and anything you could not verify. If the upgrade is not safe yet, stop, revert, and explain what blocks it.
