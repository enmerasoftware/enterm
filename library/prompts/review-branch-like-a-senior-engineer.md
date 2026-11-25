---
title: Review this branch like a senior engineer
summary: "Read every change on the current branch against its base and report real defects with file, line, a triggering input and a fix."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [review, git]
author: enmerasoftware
title_tr: Bu dalı kıdemli bir mühendis gibi incele
summary_tr: "Geçerli daldaki her değişikliği tabanına göre okur ve gerçek hataları dosya, satır, tetikleyen girdi ve düzeltmeyle raporlar."
---
Review the changes on the current branch as a senior engineer who has to sign off on them before they ship. Do not change any files.

1. Find the base: use the upstream default branch (`git symbolic-ref refs/remotes/origin/HEAD`, falling back to `main` or `master`). Run `git diff <base>...HEAD --stat`, then read the full diff. Include uncommitted changes from `git diff` and say that you did.
2. For every changed file, read the surrounding code, the callers of anything whose signature or behaviour changed, and the tests that cover it. A hunk on its own is not enough context.
3. Look for problems in this order: wrong behaviour, crashes and unhandled errors, security (unchecked input, injection, secrets, missing authorisation), data loss or corruption, concurrency and ordering, edge cases (empty, very large, unicode, time zones, null), then performance. Skip style unless it hides a bug.
4. For each finding, give: `file:line`, what goes wrong, a concrete input or sequence that triggers it, how sure you are (proven, likely, guess), and the smallest fix. If you can prove a finding by running a test or a one-off script, do it and include the command and its output.
5. Check that the change is tested: name behaviour that changed without a test that would catch a regression.
6. Run the project's test suite and linter if they exist, and report the exact command and result.

Finish with a short list of findings ordered by severity, then a one-line verdict: ready to merge, ready after the listed fixes, or not ready. Five real findings beat twenty maybes; if you found nothing serious, say so plainly.
