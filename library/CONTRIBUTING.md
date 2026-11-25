# Contributing to the Enterm Library

Thank you for sharing what works. This page covers how to submit an entry, what maintainers check before merging, and how to write a prompt that agents follow well.

**Contents:** [Ways to submit](#ways-to-submit) · [Prompt files](#prompt-files) · [Race tasks](#race-tasks) · [Skill packs](#skill-packs) · [Style guide](#style-guide) · [Review checklist](#review-checklist) · [How Enterm runs entries](#how-enterm-runs-entries) · [License](#license)

## Ways to submit

**From Enterm.** Use the **Share** button on a prompt. It opens the [prompt submission form](https://github.com/enmerasoftware/enterm/issues/new?template=submit-prompt.yml) in your browser with the text and fields filled in. Review everything, tick the boxes and submit. A maintainer turns accepted submissions into a file and credits you as the `author`.

(The form's fields are filled through URL query parameters named after their ids: `title`, `summary`, `kind`, `test`, `tags`, `prompt`, `tried` and `turkish`. Checkboxes cannot be prefilled, so you tick them yourself.)

**By pull request.**

1. Fork the repository and add `prompts/<slug>.md`, or an entry in `skills.json` for a skill pack.
2. Run `node scripts/build-index.mjs` (Node.js 20 or later, no install needed). It validates your entry and regenerates `index.json` and the table in `README.md`. Fix anything it reports.
3. Commit all three files and open a pull request. CI runs `node scripts/build-index.mjs --check`, which fails if anything is invalid or the generated files are stale.
4. In the pull request, say which agents you tried the prompt with and what they produced.

**By issue form, without Enterm.** Use [Submit a prompt or race task](https://github.com/enmerasoftware/enterm/issues/new?template=submit-prompt.yml) or [Submit a skill pack](https://github.com/enmerasoftware/enterm/issues/new?template=submit-skill.yml).

One entry per pull request or issue makes review fast. Improvements to existing entries are welcome too; explain what the change fixed in your runs.

## Prompt files

One file per prompt in `prompts/`. The file name without `.md` is the entry's id: a lowercase slug of letters, digits and single dashes. It must be unique across the library, and it should not change after merge, because people save entries by id.

```markdown
---
title: Find and fix flaky tests
summary: "Run the suite repeatedly to catch flaky tests, find why each one is flaky, and fix the cause."
kind: prompt
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [testing, debugging]
author: your-github-handle
title_tr: Kararsız testleri bul ve düzelt
summary_tr: "Kararsız testleri yakalamak için paketi tekrar tekrar çalıştırır ve nedenini düzeltir."
---
Find the flaky tests in this project and fix their causes.

1. ...
```

| Field | Required | Rules |
|---|---|---|
| `title` | yes | Sentence case, at most 60 characters, no full stop. Say what the prompt does |
| `summary` | yes | One sentence ending with a full stop, at most 200 characters |
| `kind` | yes | `prompt`, or `race` for a [race task](#race-tasks) |
| `test` | no | Race tasks only: a one-line shell command that passes when the result works |
| `programs` | yes | The programs it works well with: `claude`, `codex`, `gemini`, `opencode`, `copilot`, `cursor` |
| `tags` | yes | One to four tags from [TAGS.md](TAGS.md) |
| `author` | yes | Your GitHub handle, without `@` |
| `title_tr`, `summary_tr` | no | Turkish title and summary, both or neither. Welcome but not required; maintainers can add them |

The front matter is a small subset of YAML: `key: value`, quoted strings, and lists as `[a, b]` or as `- a` lines. Quote any value that contains a colon or starts with a special character. Everything after the closing `---` is the prompt text, sent to the agent exactly as written (leading and trailing blank lines are trimmed).

## Race tasks

A race task is given to two or three agents at once in an Enterm [race](https://github.com/enmerasoftware/enterm/blob/main/docs/race.md), each in its own git worktree, and you merge the best result. A good race task is:

- **Self-contained.** It says everything a racer needs. If it depends on the repository it runs in (for example "make the failing tests pass"), it says how to find what it needs. A kata that creates its own files must work in an empty repository.
- **Fair.** Every racer gets the same text; nothing depends on a particular agent's features. Races run with Claude Code, Codex and Gemini only, so `programs` must be a subset of those three.
- **Verifiable.** Done is something a command can check. Give `test` when the task defines it (a kata with a fixed acceptance test), and leave it out when the project's own suite is the check: Enterm detects the test command from the folder.
- **Hard to game.** Rules such as "do not edit or skip existing tests" and "do not special-case test inputs" are part of the task. A fixed acceptance test is included in the prompt for the racer to create verbatim.
- **Finished with a report.** Ask for a final message with the evidence (test output, numbers before and after). Enterm adds the instruction to commit the work, so the task can say "commit your work as the instructions below say".

## Skill packs

Skill packs are listed in `skills.json` by reference, never copied. See [skills/README.md](skills/README.md) for the format.

## Style guide

Prompts in this library are instructions for a capable colleague who cannot ask you questions. They should be:

- **Concrete.** Name the commands, files, tools and patterns to look at, with examples for common stacks. "Improve the code" is not a prompt; "find empty catch blocks and decide for each whether to log, re-throw or surface the error" is.
- **Clear about done.** Say what the finished state is and what the final report contains: a table, numbers before and after, the commands run with their results.
- **Self-verifying.** Ask the agent to check its own work: run the tests, reproduce before fixing, measure before and after, break a line to prove a new test can fail, re-run a search to show it comes back clean.
- **Honest about limits.** Ask the agent to say what it could not verify, mark guesses as guesses, and stop and ask when a decision belongs to a person.
- **Safe by default.** Prefer reporting over changing when the task is an audit. Never touch production systems, shared databases, remote branches or real users. Use the project's existing tools before adding new ones.
- **Short on fluff.** No role-play preambles, flattery, threats, all-caps or "you are the world's best". No marketing words. Numbered steps where order matters, plain sentences elsewhere.
- **Portable.** Work across agents and stacks. Avoid features of one agent unless `programs` says so, and do not hard-code paths, languages or frameworks the user may not have, unless the prompt is explicitly about them.

Titles are sentence case ("Find and fix flaky tests", not "Find And Fix Flaky Tests"). Write in English; Turkish titles and summaries go in `title_tr` and `summary_tr`.

## Review checklist

Maintainers apply this to every new or changed entry. CI catches some of it automatically; a person reads the rest.

**Every entry**

- [ ] No secrets, tokens, keys, internal hostnames, customer data or personal data.
- [ ] No destructive instructions: nothing that deletes data, rewrites published history, force-pushes, drops databases or touches production, without an explicit step that asks the user first.
- [ ] No exfiltration: nothing that sends code, environment variables, files or credentials to any outside address, pastebin, webhook or third-party service.
- [ ] No prompt-injection bait: nothing like "ignore previous instructions", "disregard the system prompt", hidden text, or instructions aimed at a different agent than the one running.
- [ ] Does not ask the agent to turn off or work around its permission prompts or sandbox (`--dangerously-skip-permissions`, `--yolo` and the like).
- [ ] No `curl … | sh` or other download-and-run steps.
- [ ] Fields are accurate: the title and summary describe what the text really does; programs and tags fit.
- [ ] Follows the [style guide](#style-guide): concrete, says what done looks like, asks the agent to verify its work.
- [ ] The author has tried it with at least one of the listed programs.

**Race tasks, additionally**

- [ ] Self-contained, fair and verifiable, as described [above](#race-tasks).
- [ ] The `test` command, if any, passes with a correct solution and fails without one. A maintainer runs it against a reference solution.

**Skill packs, additionally**

- [ ] The repository is public, and the whole pack is readable source: no minified or obfuscated files, no binaries without their source.
- [ ] A permissive, OSI-approved license (for example MIT, Apache-2.0, BSD) covers the pack.
- [ ] No network calls hidden in scripts or hooks. Any network access is stated in the skill's own instructions and needed for its job.
- [ ] No hooks or settings that change the agent's permissions, write outside the project, or modify the user's agent configuration.
- [ ] The `ref` points at the version that was reviewed. Tags or commits are preferred over branches.

A maintainer may decline an entry that passes the checklist but overlaps an existing one, or that is too narrow to help most people. Feedback comes in the pull request or issue.

## How Enterm runs entries

Enterm never runs anything from this library without showing it first. A prompt's full text is visible before you run it, and you choose the folder and the agent. A race task opens the race setup page for you to start. A skill pack shows its repository, path and ref, and is only fetched after you confirm. The agents keep their own permission prompts throughout.

That is a safety net, not a substitute for review: people run these entries on real code, so the checklist above applies to every entry.

## License

By contributing an entry you agree that it is licensed under [CC BY 4.0](LICENSE), with attribution through the `author` field and this repository. Contributions to the tooling (`scripts/`, `.github/`) are under the [MIT License](../LICENSE). Skill packs keep the license of their own repository.

Be kind in reviews and discussions; the [Enterm code of conduct](https://github.com/enmerasoftware/enterm/blob/main/CODE_OF_CONDUCT.md) applies here too.
