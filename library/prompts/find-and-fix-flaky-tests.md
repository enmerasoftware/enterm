---
title: Find and fix flaky tests
summary: "Run the suite repeatedly to catch tests that pass and fail without code changes, find why each one is flaky, and fix the cause."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [testing, debugging]
author: enmerasoftware
title_tr: Kararsız testleri bul ve düzelt
summary_tr: "Kod değişmeden bazen geçip bazen kalan testleri yakalamak için paketi tekrar tekrar çalıştırır, nedenini bulur ve kökten düzeltir."
---
Find the flaky tests in this project and fix their causes.

1. Work out how to run the tests (README, package scripts, Makefile, CI config). Run the full suite once and record the result, so you know what already fails for a real reason.
2. Run the suite at least 10 times, or the slow parts in a loop, with randomised order if the runner supports it (for example `--shuffle`, `-p random`, `--random-order`, `-count=1`). Also try running in parallel if the project normally does. Record every test that both passed and failed across runs. If CI history is available (`gh run list`), check it for tests that failed on main and passed on retry.
3. For each flaky test, find the cause before touching it. Common causes: shared state between tests, test order dependence, real time and sleeps, time zones and dates, unseeded randomness, network or filesystem access, ports in use, async work not awaited, and assertions on unordered collections. Prove the cause by making the test fail on purpose (for example run it right after the test that pollutes the state, or fix the clock to the problematic moment).
4. Fix the cause in the test or in the code. Do not add retries, longer timeouts or sleeps unless the test truly measures time, and never delete or skip a test to make it green. If a fix needs a product decision, stop and describe it.
5. Verify: run each fixed test at least 30 times in a loop and the whole suite 10 more times. All runs must pass.

Report a table: test, cause, proof, fix, runs after the fix. List any test you suspect but could not make fail.
