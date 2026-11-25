---
title: Write tests for untested code paths
summary: "Measure coverage, pick the riskiest untested branches, and cover them with tests whose assertions would actually catch a regression."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [testing]
author: enmerasoftware
title_tr: Test edilmemiş kod yollarına test yaz
summary_tr: "Kapsamı ölçer, en riskli test edilmemiş dalları seçer ve bir gerilemeyi gerçekten yakalayacak doğrulamalarla test yazar."
---
Add tests for the code paths in this project that have none, choosing the ones where a bug would hurt most.

1. Find how tests run and run them once; note what already fails. Then run coverage with the project's tool (for example `jest --coverage`, `vitest --coverage`, `pytest --cov`, `go test -cover`, `cargo llvm-cov`, `swift test --enable-code-coverage`). If no coverage tool is set up, say so and use reading instead: list public functions and branches with no test that calls them.
2. Pick up to 10 untested paths, ranked by risk: money, permissions, data writes, parsing of outside input, error handling, and anything with many branches. Say why each one made the list.
3. Write tests in the project's existing style, location and helpers. Each test must:
   - call real code, not a mock of the thing under test;
   - assert on the result or the side effect that matters (exact values, error types, what was written), never just "does not throw" or "is defined";
   - cover the edge that makes the path interesting (empty input, boundary values, the error branch).
4. Prove each test can fail: temporarily break the line it covers (flip a condition, change a constant), run the test, see it fail, then restore the code. A test that still passes against broken code gets rewritten.
5. If a test exposes a real bug, do not fix it silently: leave the test marked as expected-to-fail or skipped with a clear reason, and report the bug.

Run the whole suite at the end. Report: tests added (file and name), what each protects, coverage before and after, the mutation check for each, and any bugs found.
