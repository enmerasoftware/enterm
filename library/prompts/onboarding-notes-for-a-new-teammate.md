---
title: Explain this codebase and write onboarding notes
summary: "Map the codebase for a new teammate and write ONBOARDING.md with how to run it, how a request flows through it and where the traps are."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [onboarding, docs]
author: enmerasoftware
title_tr: Kod tabanını anlat, ekibe giriş notları yaz
summary_tr: "Yeni bir ekip arkadaşı için kod tabanının haritasını çıkarır; nasıl çalıştırılacağını, bir isteğin nasıl aktığını ve tuzakları ONBOARDING.md'ye yazar."
---
A new teammate starts tomorrow. Explore this repository and write `ONBOARDING.md` at its root so they can make a safe first change on day one. Do not change any other file.

Explore first:
1. Read the README, build files, CI config and the top-level folders. Identify languages, frameworks, entry points and how the parts talk to each other.
2. Actually run the setup, build and tests following what you found. Note every step that was missing, wrong or surprising, with the exact command that worked.
3. Pick the most important user-facing flow (for example a request to the main API, or the main screen of the app) and trace it through the code from entry to storage and back, naming real files and functions.
4. Look at `git log` for the last few months: which areas change most, and which files are touched together.

Then write `ONBOARDING.md` with these sections, each short and concrete:
- **What this is**: two or three sentences.
- **Run it**: copy-pasteable commands that you verified, with prerequisites and versions.
- **Map**: the folders that matter, one line each.
- **How a request flows**: the traced flow with file paths.
- **Where to make common changes**: for example add an endpoint, add a screen, add a migration.
- **Tests and checks**: how to run them and what CI runs.
- **Traps**: things that surprised you, generated files not to edit, slow steps, flaky areas.
- **Who and where**: owners or docs you found references to; do not invent names.

Every file path and command in the document must exist and work; check each one before you finish. Mark anything you inferred but could not verify with "(unverified)". Report the setup problems you hit separately, as candidates for fixing.
