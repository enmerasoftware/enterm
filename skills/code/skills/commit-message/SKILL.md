---
name: commit-message
description: Write a clear commit message for the staged changes. Use when the user asks for a commit message or to commit.
---

# Commit message

1. Read `git diff --cached` (or `git diff` if nothing is staged, and say so). Read `git log -10 --format=%s` to match the project's style.
2. Subject: what the change does for the user, imperative, under 72 characters, no trailing period. Follow the project's convention (Conventional Commits only if the log uses them).
3. Body only when the why is not obvious: the reason, and anything a reviewer should know. Wrap at 72.
4. Do not commit or push unless the user asked. Never add files the user did not mean to include; list untracked files and ask.
