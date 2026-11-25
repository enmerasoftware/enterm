---
title: Split a large file into focused modules
summary: "Break the largest, most-changed file into cohesive modules without changing behaviour, moving code in mechanical steps that each keep the tests green."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [refactor]
author: enmerasoftware
title_tr: Büyük bir dosyayı odaklı modüllere böl
summary_tr: "En büyük ve en sık değişen dosyayı davranışı değiştirmeden uyumlu modüllere ayırır; her adımda testlerin geçtiği mekanik taşımalar yapar."
---
Split one oversized file in this project into smaller, focused modules without changing behaviour.

1. Pick the file. If I did not name one, find files over about 800 lines and rank them by how often they change (`git log --format= --name-only | sort | uniq -c | sort -rn | head -30`). Pick the one that is both large and frequently changed, and say why.
2. Run the build and tests and record the result. If the file has little test coverage, add characterisation tests for its public behaviour first, so the refactor has a safety net.
3. Read the whole file and group its contents by responsibility: what changes together and what depends on what. Propose the new module layout (names, what goes where, what stays as the public entry point) in a short list before moving code.
4. Move code in small mechanical steps: one group at a time, cut and paste with only the imports and visibility changes needed. Do not rename, rewrite or "improve" logic while moving it. Keep the original file's public API working by re-exporting from it, so callers do not need to change in this pass.
5. After each step, build and run the tests. Commit-sized steps are fine but do not commit unless I ask.
6. Check for circular imports and for anything that relied on file-level state.

Report: the file and its size before, the new modules with their sizes and responsibilities, confirmation that the public API is unchanged, and the test results after each step. Suggest follow-up clean-ups separately; do not do them now.
