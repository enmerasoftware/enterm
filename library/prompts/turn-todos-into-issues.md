---
title: Turn TODO comments into issues
summary: "Collect every TODO, FIXME and HACK comment, group and triage them, and draft issues you can file with one command after you review them."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [git, docs]
author: enmerasoftware
title_tr: TODO yorumlarını iş kayıtlarına dönüştür
summary_tr: "Tüm TODO, FIXME ve HACK yorumlarını toplar, gruplar ve önceliklendirir; gözden geçirdikten sonra tek komutla açabileceğin iş kayıtları taslağı hazırlar."
---
Turn the TODO comments in this repository into well-written issue drafts. Do not create any issue and do not edit source files.

1. Search tracked files for `TODO`, `FIXME`, `HACK`, `XXX` and `@todo` (for example `git grep -n -E "TODO|FIXME|HACK|XXX"`), skipping vendored and generated folders. For each hit, record the file, line, the comment, and `git blame` for its author and date.
2. Read the code around each one so you understand what is actually missing. Drop comments that are already done (the code does what the TODO asks), and say which ones and why.
3. Group TODOs that describe the same work into one issue. Check open issues (`gh issue list --state open --limit 200` if `gh` is available) and mark drafts that duplicate an existing issue instead of drafting them again.
4. Write `TODO-ISSUES.md` with one section per draft issue:
   - a title in sentence case that says the outcome;
   - what is wrong or missing today, and why it matters, in two to four sentences;
   - links to the exact lines (`path:line`);
   - a suggested label (bug, enhancement, tech debt, docs) and a size (small, medium, large);
   - what done looks like, as a checklist.
5. At the end of the file, add a shell script block that would create each issue with `gh issue create --title ... --body-file ...`, so I can run it after reviewing. Do not run it.

Report how many TODOs you found, how many were already done, how many drafts you wrote, and the five you think matter most.
