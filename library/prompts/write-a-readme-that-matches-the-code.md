---
title: Write a README that matches the code
summary: "Rewrite the README from what the code actually does, with install and usage steps you have run yourself."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [docs, onboarding]
author: enmerasoftware
title_tr: Koda uyan bir README yaz
summary_tr: "README'yi kodun gerçekte yaptığına göre yeniden yazar; kurulum ve kullanım adımlarını bizzat çalıştırarak doğrular."
---
Rewrite this project's `README.md` so that it is accurate, short and useful to someone who has never seen the project. Change only the README.

1. Read the current README, then the code: entry points, CLI flags or public API, configuration and environment variables, build and test scripts, license. Make a list of every claim in the current README that is wrong, outdated or missing.
2. Run the install and the main usage examples exactly as you will document them, in a clean way (for example a fresh clone in a temporary folder). Fix the steps until they work, and use the commands that worked.
3. Structure:
   - Name and one sentence on what it does and for whom.
   - A minimal example that shows the main thing working, with its real output.
   - Install, with prerequisites and versions.
   - Usage: the common tasks, then a reference of options or configuration in a table (every environment variable the code reads, its default and what it does).
   - Development: build, test, lint.
   - License, and links to contributing and changelog if they exist.
4. Style: plain sentences, no marketing words, no badges that do not work, no features that do not exist. Keep any section of the old README that is still correct and valuable.

Check every command, path, flag and link in the new README against the code or by running it. Report the list of corrections you made to the old README's claims, and anything you could not verify, marked in the README as well.
