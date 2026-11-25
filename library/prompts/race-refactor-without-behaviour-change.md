---
title: Refactor a module without changing behaviour
summary: "Race to make one tangled module easier to read and change while every existing test keeps passing and the public API stays the same."
kind: race
programs: [claude, codex, gemini]
tags: [refactor, testing]
author: enmerasoftware
title_tr: Bir modülü davranışını değiştirmeden yeniden düzenle
summary_tr: "Tüm mevcut testler geçmeye ve genel API aynı kalmaya devam ederken karmaşık bir modülü okunur ve değiştirilebilir hale getirme yarışı."
---
Refactor the most tangled module in this repository so that it is easier to read and change, without changing its behaviour. If I named a module, use that one. Otherwise pick the source file with the highest combination of length, nesting depth and change frequency (`git log --format= --name-only | sort | uniq -c | sort -rn | head -20`), and say which one you picked and why in your final message.

Rules:
- Behaviour must not change: same inputs, same outputs, same side effects, same errors. The module's public API (exported names, signatures, return types) stays exactly as it is.
- Every existing test must still pass, and you must not edit existing tests.
- No new dependencies.

Steps:
1. Run the full test suite and record the result. If the module has weak coverage, first add characterisation tests that pin down its current behaviour, including edge cases and error paths, and make sure they pass before you refactor.
2. Improve the structure: smaller functions with clear names, early returns instead of deep nesting, duplicated logic extracted once, magic values named, dead branches removed (with proof that they are dead). Prefer several small, safe steps over one rewrite.
3. Run the full test suite after each step.

Finish with the full suite passing. In your final message, give the module, a before and after summary (lines, longest function, deepest nesting), the tests you added, and the final test command with its result. Then commit your work as the instructions below say.
