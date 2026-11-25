---
title: Add a CI workflow that runs the checks
summary: "Add a GitHub Actions workflow that installs from the lock file, builds, lints and tests on every push and pull request, and is fast and cached."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [ci, testing]
author: enmerasoftware
title_tr: Kontrolleri çalıştıran bir CI iş akışı ekle
summary_tr: "Her push ve pull request'te kilit dosyasından kurup derleyen, lint ve test çalıştıran, hızlı ve önbellekli bir GitHub Actions iş akışı ekler."
---
Add continuous integration to this repository with GitHub Actions (or improve the existing workflow if there is one).

1. Find the commands a developer runs: install, build, type-check, lint, format check and tests, from the README, package scripts, Makefile or similar. Run each one locally first and note which pass today. A workflow that fails on day one helps nobody: if a check fails now, keep it out of the required job and list it for me.
2. Write `.github/workflows/ci.yml`:
   - triggers on `push` to the default branch and on `pull_request`;
   - `permissions: contents: read` unless a step needs more;
   - pinned runtime versions that match the project (read `.nvmrc`, `.python-version`, `go.mod`, `rust-toolchain`, `engines` and the like);
   - install from the lock file (`npm ci`, `pnpm install --frozen-lockfile`, `pip install -r` with hashes or `uv sync --frozen`, and so on) with the setup action's built-in caching;
   - one job per concern only if that makes it faster or clearer; a matrix only for versions or platforms the project claims to support;
   - `concurrency` that cancels superseded runs on the same branch;
   - a timeout on each job.
3. Use only well-known actions and pin them to a major version tag at least; never add a step that sends code or secrets to a third-party service.
4. Validate the YAML (for example `actionlint` if available) and, if `act` is installed, run the workflow locally.

Do not push. Report the workflow, the commands it runs, the checks you left out and why, and the expected run time.
