---
title: Make the failing tests pass
summary: "Race to turn a red test suite green by fixing the code under test, never by weakening, skipping or deleting tests."
kind: race
programs: [claude, codex, gemini]
tags: [testing, debugging]
author: enmerasoftware
title_tr: Kalan testleri geçir
summary_tr: "Kırmızı bir test paketini, testleri zayıflatmadan, atlamadan veya silmeden, test edilen kodu düzelterek yeşile çevirme yarışı."
---
The test suite in this repository has failing tests. Make the whole suite pass by fixing the code under test.

Rules:
- Do not edit, skip, delete or weaken any existing test, assertion, fixture or snapshot, and do not change test configuration to exclude tests. If you are convinced a test itself is wrong, leave it failing and explain why in your final message.
- Do not special-case test inputs in production code.
- Keep changes as small as the causes allow; do not refactor unrelated code.

Steps:
1. Find the test command (README, package scripts, Makefile, CI config) and run the full suite. List every failing test with its error.
2. Group failures by likely shared cause. For each cause, read the code, state the cause in one sentence, and fix it.
3. Run the full suite after each fix to make sure you did not break anything else.
4. Finish when the full suite passes, or when the only failures left are tests you believe are wrong.

In your final message, list each cause, the fix (file and line), and the final test command with its pass count. Then commit your work as the instructions below say.
