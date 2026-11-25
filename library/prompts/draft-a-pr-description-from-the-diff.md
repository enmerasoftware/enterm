---
title: Draft a pull request description from the diff
summary: "Read the branch's commits and diff and write a pull request description that says what changed, why, how it was tested and what to look at."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [git, docs]
author: enmerasoftware
title_tr: Farktan bir pull request açıklaması hazırla
summary_tr: "Dalın commit'lerini ve farkını okur; neyin neden değiştiğini, nasıl test edildiğini ve nereye bakılması gerektiğini anlatan bir PR açıklaması yazar."
---
Write a pull request description for the current branch. Do not push, open the pull request or change code.

1. Find the base branch (the repository's default branch unless I say otherwise). Read `git log <base>..HEAD` and the full `git diff <base>...HEAD`. Read enough of the surrounding code to understand why each change was made.
2. If the repository has a pull request template (`.github/pull_request_template.md` or similar), follow it exactly. Otherwise use these sections:
   - **What**: one or two sentences on the change from the user's or caller's point of view.
   - **Why**: the problem or the goal; link the issue if a commit or the branch name references one.
   - **How**: the approach and any decision a reviewer might question, with the alternative you or the author rejected.
   - **Testing**: what was tested and how. Run the test suite now and include the command and the result; list manual checks that still need doing.
   - **Risk and rollout**: migrations, config or environment changes, feature flags, backwards compatibility, anything to watch after deploy.
   - **Review guide**: the files to read first and the ones that are mechanical.
3. Write it for a reviewer who has not seen the work: plain language, no marketing words, no restating of every file. Mention screenshots that should be attached if the UI changed.
4. Suggest a title in sentence case, under 72 characters, that says what the change does.

Save it to `PR_DESCRIPTION.md` (not committed) and print it. Point out anything in the diff that looks unfinished or accidental, such as debug output, commented-out code or unrelated changes.
