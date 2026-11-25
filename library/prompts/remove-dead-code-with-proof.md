---
title: Remove dead code with proof
summary: "Find code that nothing calls, prove each piece is unreachable, remove it in small steps, and show the build and tests still pass."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [refactor]
author: enmerasoftware
title_tr: Ölü kodu kanıtla birlikte kaldır
summary_tr: "Hiçbir yerden çağrılmayan kodu bulur, her parçanın erişilemez olduğunu kanıtlar, küçük adımlarla siler ve derleme ile testlerin hâlâ geçtiğini gösterir."
---
Find and remove dead code in this project, with proof for every deletion.

1. Run the build and the test suite and record the result as the baseline.
2. Find candidates with the stack's tools where available (for example `ts-prune` or `knip` for TypeScript, `vulture` for Python, `staticcheck` or `deadcode` for Go, `cargo +nightly udeps` and compiler warnings for Rust, Periphery for Swift), plus a search for unused exports, files nothing imports, feature flags that are always on or off, and branches for platforms or versions the project no longer supports.
3. For each candidate, prove it is dead before deleting it. Search the whole repository for its name, including strings, configs, templates, scripts, docs and tests. Be careful with code reached dynamically: reflection, dependency injection, routes registered by name, serializers, public library APIs, plugin entry points, migrations, and anything called from another repository. If you cannot prove it, leave it and list it as "probably dead".
4. Delete in small groups, by area. After each group, build and run the tests. If something breaks, put it back and note why it was not dead.
5. Remove things that only existed for the dead code: their tests, fixtures, helpers and dependencies in the package manifest, again with proof.

Report a table: what was removed, its size in lines, and the proof (for example "no references outside its own file; not exported from the package index; not named in any config"). Give the total lines removed, the final build and test results, and the list of suspicious code you left with the reason.
