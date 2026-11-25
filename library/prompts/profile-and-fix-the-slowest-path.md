---
title: Profile and fix the slowest path
summary: "Measure where time actually goes in a slow operation, fix the biggest cost, and prove the speed-up with before and after numbers."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [performance]
author: enmerasoftware
title_tr: En yavaş yolu ölç ve hızlandır
summary_tr: "Yavaş bir işlemde zamanın gerçekte nereye gittiğini ölçer, en büyük maliyeti düzeltir ve hızlanmayı önce ve sonra sayılarıyla kanıtlar."
---
Make the slowest important path in this project faster, guided by measurement, not by guessing.

1. Decide what to measure. If I named an operation, use it. Otherwise find the hot path: the main request, the build step, the startup, or the slowest tests (`--durations`, `--verbose` timings). Say what you picked and why.
2. Write a repeatable benchmark or timing script for it with realistic data size. Run it at least 5 times and record the median and spread. This is the baseline.
3. Profile it with the right tool for the stack (for example `node --cpu-prof`, `py-spy`, `cProfile`, `pprof`, Instruments or `perf`, the database's `EXPLAIN ANALYZE`). Find where most of the time goes. Do not optimise anything that is under 5% of the total.
4. Fix the biggest cost. Typical wins: N+1 queries, missing indexes, repeated work in a loop, unnecessary serialisation, blocking I/O on the hot path, missing caching of pure results, quadratic algorithms. Keep behaviour identical.
5. Run the test suite; it must pass unchanged. Run the benchmark again the same way and compare medians.
6. Repeat steps 3 to 5 only while each change gives a clear win. Stop when the remaining costs are spread out or need a design decision.

Report: what you measured, the baseline, a table of changes with the time each one saved, the final number and the speed-up ratio, the profiler evidence for each change, and the ideas you did not do with their expected gain. Leave the benchmark script in the repo if it is useful, and say where.
