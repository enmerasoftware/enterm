---
name: review
description: Review a diff or branch for real defects: wrong behaviour, crashes, security holes, data loss, missing edge cases. Use when the user asks for a code review or before merging.
---

# Review

1. Get the change: `git diff` for local work, `git diff origin/<base>...HEAD` for a branch, `gh pr diff <n>` for a pull request.
2. Read every changed file around the change, not only the hunk.
3. Look for, in this order: wrong behaviour, crashes and unhandled errors, security (injection, secrets, unchecked input, permissions), data loss, concurrency, edge cases (empty, huge, unicode, time zones), then performance.
4. For each finding give file:line, what breaks, a concrete input that triggers it, and a fix. Leave style nits out unless the user asked.
5. If a finding is a guess, mark it as such. Better five real findings than twenty maybe.
6. End with a one-line verdict: ready, ready after fixes, or not ready.
