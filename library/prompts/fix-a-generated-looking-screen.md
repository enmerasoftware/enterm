---
title: Fix a screen that looks AI-generated
summary: "Measure a screen with ai-design-check, fix the generic choices that make it look generated, and show the findings before and after."
kind: prompt
programs: [claude, codex]
tags: [design, frontend, mobile]
author: enmerasoftware
title_tr: Yapay zekâ üretimi gibi görünen bir ekranı düzelt
summary_tr: "Bir ekranı ai-design-check ile ölçer, onu üretilmiş gösteren sıradan tercihleri düzeltir ve bulguları önce ve sonra gösterir."
---
Improve the design of one screen in this project so it stops looking generated, without changing its features, data or wording. If I did not name the screen, ask which one, or pick the main screen and say so.

Use the ai-design-check rules and checker. If the `ai-design-check` skill pack is loaded, follow its `ai-design-fix` skill. Otherwise run the checker with `npx @enmera/ai-design-check <path>` and read its rules with `npx @enmera/ai-design-check rules`.

1. Measure first: run the checker on the files of this screen and save the output. Take a screenshot of the screen as it is now if you can run it, or note the commit so a before and after comparison is possible.
2. Write a three-line brief at the top of your report: who uses this screen, the one job they come to do, and what the product should feel like. Use what the code and README say; do not invent a brand.
3. Fix in this order, and only what the findings or the brief justify: usability (the main action, what is in its way), truthful states (loading, empty, error), copy (sentence case, plain labels), numbers (locale formatting), components (reuse the shared ones instead of one-off styles), spacing and type scale, then decoration (gradients, glows, emoji, endless animation).
4. Make each change in the shared component or theme where possible, so the fix holds everywhere.
5. Run the checker again and the project's build and tests.

Report the finding counts before and after per rule, a list of changes with the reason for each, screenshots before and after if you could take them, and anything you left because it needs a product decision.
