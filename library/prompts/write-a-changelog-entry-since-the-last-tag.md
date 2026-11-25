---
title: Write the changelog entry since the last release
summary: "Read the commits and merged pull requests since the last tag and write a changelog entry that users can understand."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [docs, git]
author: enmerasoftware
title_tr: Son sürümden bu yana değişiklik günlüğünü yaz
summary_tr: "Son etiketten bu yana gelen commit'leri ve birleşen pull request'leri okur ve kullanıcıların anlayacağı bir değişiklik günlüğü girdisi yazar."
---
Write the changelog entry for the next release of this project.

1. Find the last release: `git describe --tags --abbrev=0`. List the changes since then with `git log <tag>..HEAD --no-merges --format="%h %s"` and, if `gh` is available, the merged pull requests since the tag's date. Read the diff of any commit whose message does not make the change clear.
2. Find the changelog format: an existing `CHANGELOG.md` (follow its style exactly), or Keep a Changelog if there is none. Work out the next version number from semantic versioning: breaking changes make a major, new features a minor, fixes only a patch. Say which and why.
3. Write entries for users, not for developers: what they can now do, what works better, what was fixed and how they would have noticed it. Group under Added, Changed, Fixed, Removed, Security, and a clear **Breaking** note at the top with migration steps if anything breaks.
4. Leave out internal changes that users cannot notice (refactors, test changes, CI), unless the project's changelog includes them. Merge several commits about the same thing into one entry. Credit outside contributors the way the project does.
5. Every entry must be backed by a commit or PR; add the reference in the project's style.

Insert the entry at the top of `CHANGELOG.md` under an "Unreleased" heading with the proposed version, and do not tag or bump the version. Report the commits you left out and why, and anything that looked like a breaking change but was not labelled as one.
