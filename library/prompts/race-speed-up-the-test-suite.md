---
title: Speed up the test suite
summary: "Race to cut the test suite's wall-clock time the most, with the same tests passing and no test removed or skipped."
kind: race
programs: [claude, codex, gemini]
tags: [testing, performance]
author: enmerasoftware
title_tr: Test paketini hızlandır
summary_tr: "Aynı testler geçmeye devam ederken ve hiçbir test silinmeden veya atlanmadan test paketinin süresini en çok kısaltma yarışı."
---
Make this repository's full test suite run faster, measured by wall-clock time.

Rules:
- The same set of tests must run and pass: do not delete, skip, merge away or weaken tests or assertions.
- Do not change production behaviour to make tests faster, unless it is a real performance fix that you explain.
- Do not depend on caches that only exist on your machine; the speed-up must hold on a clean checkout.

Steps:
1. Find the test command and run the full suite 3 times. Record the number of tests and the median time. This is the baseline.
2. Find where the time goes: per-test durations (for example `--durations=20`, `--reporter=verbose`, `-v` with timings), setup and teardown, and the runner's startup.
3. Fix the biggest costs first. Typical wins: real sleeps and timeouts replaced by fake timers or a fake clock, expensive setup done once per file instead of once per test, database reset by transaction rollback instead of re-creation, network calls replaced by local fakes where tests should not hit the network anyway, parallel workers if tests are isolated, and transforms or compilation steps that run more than needed.
4. After each change, run the full suite and check the test count is unchanged and everything passes.

Finish by running the full suite 3 times again. In your final message, give the test count and median time before and after, the speed-up ratio, and each change with the time it saved. Then commit your work as the instructions below say.
