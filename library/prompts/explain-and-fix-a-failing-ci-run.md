---
title: Explain and fix a failing CI run
summary: "Read the logs of a failing CI run, reproduce the failure locally, fix the cause, and say why it passed on your machine."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [ci, debugging]
author: enmerasoftware
title_tr: Kırmızı bir CI çalışmasını açıkla ve düzelt
summary_tr: "Başarısız bir CI çalışmasının kayıtlarını okur, hatayı yerelde yeniden üretir, nedeni düzeltir ve neden yerelde geçtiğini açıklar."
---
The latest CI run on this branch is failing. Find out why and fix it.

1. Get the logs. With GitHub Actions: `gh run list --branch "$(git branch --show-current)" --limit 5`, then `gh run view <id> --log-failed`. For other CI systems, ask me for the log if you cannot fetch it. Quote the first real error, not the last line.
2. Classify it: a real test failure, a build or type error, lint, a missing secret or permission, a dependency or cache problem, an environment difference (OS, runtime version, time zone, locale, case-sensitive file system, CPU count), or a flaky test. Check whether the same job fails on the default branch too (`gh run list --branch main`).
3. Reproduce locally with the same command the workflow runs, and match the environment where it matters (for example the same Node, Python or Xcode version, `TZ=UTC`, `CI=true`, a clean install from the lock file). If you cannot reproduce it, explain what differs and how you know.
4. Fix the cause. If it is the code, fix the code. If it is the workflow, change the workflow. Do not mark tests as skipped, raise timeouts or add retries to get to green, unless you prove the test is flaky for reasons outside this change and say so.
5. Verify by running the failing step locally until it passes, then the full suite. Do not push; tell me it is ready to push.

Report: the failing step, the error, the cause in one sentence, why it passed locally before, the fix, and the commands you used to verify it.
