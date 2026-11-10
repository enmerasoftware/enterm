---
name: release-check
description: Check that a project is ready to release: tests, version number, changelog, build, uncommitted files and tags. Use before tagging, publishing or shipping a version.
---

# Release check

Report a checklist with a clear yes or no for each line. Change nothing without asking.

1. Branch and state: current branch, `git status` clean, up to date with the remote.
2. Tests: run the project's suite and report the numbers.
3. Version: find where the version lives (package.json, Info.plist, Cargo.toml, pyproject, etc.) and check it is higher than the last tag (`git describe --tags --abbrev=0`).
4. Changelog or release notes mention the changes since the last tag (`git log <last-tag>..HEAD --oneline`).
5. Build: run the release build command if there is one; report warnings that look new.
6. Secrets: `git diff <last-tag>..HEAD` contains no keys, tokens or `.env` files.
7. Say what is missing and the exact command to fix each item.
