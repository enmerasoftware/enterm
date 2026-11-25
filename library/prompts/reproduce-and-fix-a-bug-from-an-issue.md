---
title: Reproduce and fix a bug from an issue
summary: "Turn a bug report into a failing test, find the real cause, fix it with the smallest change, and show the test passing."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [debugging, testing]
author: enmerasoftware
title_tr: Bir hata kaydını yeniden üret ve düzelt
summary_tr: "Bir hata raporunu başarısız bir teste çevirir, gerçek nedeni bulur, en küçük değişiklikle düzeltir ve testin geçtiğini gösterir."
---
Fix the bug described below (or in the issue I link; read it with `gh issue view <number>` if `gh` is available). If there is no description yet, ask me for it before you start.

1. Restate the bug in one sentence: the input, what happens, and what should happen. List any detail the report is missing and the assumption you are making.
2. Reproduce it before changing anything. Write an automated test that fails because of the bug, in the project's existing test style. If a test is not possible, write the smallest script or exact steps that show the failure. Run it and paste the failure. If you cannot reproduce it, stop and say what you tried and what you need.
3. Find the cause. Read the code path from the entry point; test one hypothesis at a time with the cheapest check (a log line, a debugger, a small script, `git bisect` if it used to work). Drop a hypothesis as soon as a check disproves it. State the cause in one sentence with the file and line.
4. Fix the cause, not the symptom, with the smallest change that does it. Do not refactor nearby code. Look for the same mistake elsewhere in the codebase and list where it appears.
5. Verify: the new test passes, the full suite passes, and the original reproduction steps now give the expected result.

Report: the cause, the proof, the fix, the test you added, the commands you ran with their results, and other places with the same pattern. Draft a short comment for the issue explaining the fix.
