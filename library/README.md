<div align="center">

# Enterm Library

**Prompts, race tasks and skill packs for AI coding agents, ready to run in [Enterm](https://github.com/enmerasoftware/enterm).**

Reviewed by people, checked by CI, and never run without being shown to you first.

[![Index](https://img.shields.io/github/actions/workflow/status/enmerasoftware/enterm/library.yml?branch=main&label=index&labelColor=14181a)](https://github.com/enmerasoftware/enterm/actions/workflows/library.yml)
[![Tooling: MIT](https://img.shields.io/badge/tooling-MIT-7fa6ff?labelColor=14181a)](../LICENSE)
[![Content: CC BY 4.0](https://img.shields.io/badge/content-CC%20BY%204.0-86d19a?labelColor=14181a)](LICENSE)

[Browse the library](#whats-inside) ·
[Contribute](CONTRIBUTING.md) ·
[Tags](TAGS.md) ·
[Enterm](https://github.com/enmerasoftware/enterm) ·
[Türkçe](#türkçe)

</div>

---

## What this is

A shared collection of the instructions that work well with today's coding agents: Claude Code, Codex, Gemini, opencode, GitHub Copilot and Cursor. Three kinds of entries:

| Kind | What it is | Where it lives |
|---|---|---|
| **Prompt** | A task you give one agent, written so that it says what done looks like and how the agent should check its own work | `prompts/<slug>.md` |
| **Race task** | A task meant for several agents at once in an Enterm [race](https://github.com/enmerasoftware/enterm/blob/main/docs/race.md): fair, self-contained, and verifiable, often with a test command | `prompts/<slug>.md` with `kind: race` |
| **Skill pack** | A Claude Code plugin with skills, listed here by reference to its own repository, never copied | `skills.json` |

Everything is plain text. You can read every entry on GitHub, copy it into any agent by hand, or use it from Enterm with one click.

## Using it from Enterm

Enterm's **Library** page reads [`index.json`](index.json) from this repository.

- **Browse** by kind, tag or program, in English or Turkish. Each entry shows the full prompt text before you do anything with it.
- **Save** an entry to keep it in your own list, available offline.
- **Run** a prompt with one click: pick the folder and the agent, and Enterm opens a session with the text as its first message. You see the exact text first; nothing starts until you confirm.
- **Race** a race task: Enterm opens the Start a Race page with the task and its test command filled in. You pick the racers and start it yourself.
- **Add a skill**: Enterm shows the repository, path and ref of the pack, fetches it at that ref, and adds it to your preset packs. It is loaded per session with `--plugin-dir`, never written to `~/.claude`, and you can turn it off in Settings.
- **Share** your own prompt from Enterm: the Share button opens this repository's submission form with the fields filled in, for you to review and send.

No Enterm? Every prompt is a Markdown file. The text after the front matter is exactly what is sent to the agent.

## Safety model

Prompts are instructions an agent will follow on your machine, so this library treats them like code.

1. **Reviewed before merge.** Every entry is read by a maintainer against the [review checklist](CONTRIBUTING.md#review-checklist): no secrets, no destructive or data-exfiltrating instructions, no prompt-injection bait, and for skills readable source, a permissive license and no hidden network calls.
2. **Checked by CI.** [`scripts/build-index.mjs`](scripts/build-index.mjs) validates every field and rejects known-dangerous patterns (for example "ignore previous instructions", piping a download into a shell, or turning off an agent's permission checks) on every push and pull request.
3. **Shown before it runs.** Enterm never runs an entry without showing you its full text, or, for a skill, its source location, first. The agents keep their own permission prompts; nothing in this library turns them off.
4. **Pinned skills.** A skill entry names a repository, a path and a ref. Prefer a tag or a commit for anything you rely on.

Found something unsafe? Open an issue, or for anything sensitive, follow the [Enterm security policy](https://github.com/enmerasoftware/enterm/security/policy).

## Contributing

New prompts, race tasks and skill packs are welcome. In short:

- **From Enterm:** use the Share button on a prompt; it opens the [submission form](https://github.com/enmerasoftware/enterm/issues/new?template=submit-prompt.yml).
- **By pull request:** add `prompts/<slug>.md` (or an entry in `skills.json`), run `node scripts/build-index.mjs`, and commit the regenerated `index.json` and README.

The format, the style guide and the review checklist are in [CONTRIBUTING.md](CONTRIBUTING.md). The allowed tags are in [TAGS.md](TAGS.md).

### Format at a glance

```markdown
---
title: Review this branch like a senior engineer
summary: "Read every change on the current branch and report real defects with a fix."
kind: prompt            # or race
programs: [claude, codex, gemini, opencode, copilot, cursor]
tags: [review, git]     # from TAGS.md
author: your-github-handle
title_tr: Bu dalı kıdemli bir mühendis gibi incele      # optional
summary_tr: "Geçerli daldaki her değişikliği inceler."   # optional
# test: npm test        # race tasks only, optional
---
The exact text the agent receives.
```

### Building the index

Requires Node.js 20 or later; no install step, no dependencies.

```bash
node scripts/build-index.mjs           # validate, write index.json and the table below
node scripts/build-index.mjs --check   # validate only; fails if index.json or this README is stale
```

## What's inside

This table is generated from the entries; do not edit it by hand.

<!-- index:start -->

### Prompts (26)

| Prompt | What it does | Tags |
|---|---|---|
| [Accessibility pass on a screen](prompts/accessibility-pass-on-a-screen.md) | Check one screen for keyboard use, screen reader names, focus, contrast and text size, fix what fails, and verify each fix. | accessibility, frontend, mobile |
| [Add a CI workflow that runs the checks](prompts/add-a-ci-workflow.md) | Add a GitHub Actions workflow that installs from the lock file, builds, lints and tests on every push and pull request, and is fast and cached. | ci, testing |
| [Add contract tests for an HTTP API](prompts/add-api-contract-tests.md) | Write tests that pin down each endpoint's status codes, response shapes and error formats, so an accidental breaking change fails the build. | testing, backend |
| [Add loading, empty and error states to a screen](prompts/add-loading-empty-and-error-states.md) | Make a data-driven screen honest about every state it can be in, with clear copy and a way out of each error, and test each state. | frontend, mobile, design |
| [Add structured logging to a service](prompts/add-structured-logging.md) | Replace ad hoc print and log calls on the main paths with structured, levelled logs that carry a request ID and never leak secrets. | observability, backend |
| [Audit error handling for swallowed failures](prompts/audit-error-handling.md) | Find errors that are caught and ignored, logged without context or turned into wrong results, and make each failure visible and handled. | review, backend, observability |
| [Draft a pull request description from the diff](prompts/draft-a-pr-description-from-the-diff.md) | Read the branch's commits and diff and write a pull request description that says what changed, why, how it was tested and what to look at. | git, docs |
| [Explain and fix a failing CI run](prompts/explain-and-fix-a-failing-ci-run.md) | Read the logs of a failing CI run, reproduce the failure locally, fix the cause, and say why it passed on your machine. | ci, debugging |
| [Explain this codebase and write onboarding notes](prompts/onboarding-notes-for-a-new-teammate.md) | Map the codebase for a new teammate and write ONBOARDING.md with how to run it, how a request flows through it and where the traps are. | onboarding, docs |
| [Find and fix flaky tests](prompts/find-and-fix-flaky-tests.md) | Run the suite repeatedly to catch tests that pass and fail without code changes, find why each one is flaky, and fix the cause. | testing, debugging |
| [Find and fix N+1 database queries](prompts/find-and-fix-n-plus-one-queries.md) | Count the queries each main endpoint makes, find loops that query once per row, batch them, and prove the counts dropped. | performance, data, backend |
| [Fix a screen that looks AI-generated](prompts/fix-a-generated-looking-screen.md) | Measure a screen with ai-design-check, fix the generic choices that make it look generated, and show the findings before and after. | design, frontend, mobile |
| [Harden input validation at the edges](prompts/harden-input-validation.md) | Find every place outside input enters the system, validate it at that boundary with clear errors, and add tests for hostile inputs. | security, backend |
| [Move hardcoded UI text into translation keys](prompts/add-i18n-keys-for-hardcoded-strings.md) | Find user-facing strings written directly in the UI code, move them into the project's translation files with good keys, and check nothing is left. | i18n, frontend, mobile |
| [Profile and fix the slowest path](prompts/profile-and-fix-the-slowest-path.md) | Measure where time actually goes in a slow operation, fix the biggest cost, and prove the speed-up with before and after numbers. | performance |
| [Remove dead code with proof](prompts/remove-dead-code-with-proof.md) | Find code that nothing calls, prove each piece is unreachable, remove it in small steps, and show the build and tests still pass. | refactor |
| [Reproduce and fix a bug from an issue](prompts/reproduce-and-fix-a-bug-from-an-issue.md) | Turn a bug report into a failing test, find the real cause, fix it with the smallest change, and show the test passing. | debugging, testing |
| [Review this branch like a senior engineer](prompts/review-branch-like-a-senior-engineer.md) | Read every change on the current branch against its base and report real defects with file, line, a triggering input and a fix. | review, git |
| [Security audit of the authentication flows](prompts/security-audit-of-auth-flows.md) | Trace sign-up, sign-in, sessions, password reset and authorisation checks, and report exploitable weaknesses with proof and a fix. | security, review, backend |
| [Split a large file into focused modules](prompts/split-a-large-file-into-modules.md) | Break the largest, most-changed file into cohesive modules without changing behaviour, moving code in mechanical steps that each keep the tests green. | refactor |
| [Turn TODO comments into issues](prompts/turn-todos-into-issues.md) | Collect every TODO, FIXME and HACK comment, group and triage them, and draft issues you can file with one command after you review them. | git, docs |
| [Upgrade a dependency safely](prompts/upgrade-a-dependency-safely.md) | Upgrade one dependency to its latest major version, read its changelog for breaking changes, adapt the code and prove nothing regressed. | dependencies, refactor |
| [Write a database migration with a rollback](prompts/write-a-migration-with-rollback.md) | Write a schema or data migration that runs safely on a live database, with a tested rollback and a plan for existing rows. | data, backend |
| [Write a README that matches the code](prompts/write-a-readme-that-matches-the-code.md) | Rewrite the README from what the code actually does, with install and usage steps you have run yourself. | docs, onboarding |
| [Write tests for untested code paths](prompts/test-untested-code-paths.md) | Measure coverage, pick the riskiest untested branches, and cover them with tests whose assertions would actually catch a regression. | testing |
| [Write the changelog entry since the last release](prompts/write-a-changelog-entry-since-the-last-tag.md) | Read the commits and merged pull requests since the last tag and write a changelog entry that users can understand. | docs, git |

### Race tasks (7)

| Race task | What it does | Tags |
|---|---|---|
| [Cover the least-tested module with real tests](prompts/race-cover-the-least-tested-module.md) | Race to raise test coverage of the least-tested important module with tests that fail when the code is broken. | testing |
| [Kata: a correct CSV parser in JavaScript](prompts/race-csv-parser.md) | Race to write an RFC 4180 CSV parser and writer that handles quotes, newlines in fields and clear errors, verified by a fixed acceptance test. | data, testing |
| [Kata: a token bucket rate limiter in Python](prompts/race-token-bucket-rate-limiter.md) | Race to build a token bucket and a per-key limiter with an injectable clock and bounded memory, verified by a fixed pytest suite. | backend, testing |
| [Kata: an LRU cache with expiry in JavaScript](prompts/race-lru-cache-with-ttl.md) | Race to implement a fast, dependency-free LRU cache with per-entry expiry that passes a fixed acceptance test. | testing, performance |
| [Make the failing tests pass](prompts/race-make-the-failing-tests-pass.md) | Race to turn a red test suite green by fixing the code under test, never by weakening, skipping or deleting tests. | testing, debugging |
| [Refactor a module without changing behaviour](prompts/race-refactor-without-behaviour-change.md) | Race to make one tangled module easier to read and change while every existing test keeps passing and the public API stays the same. | refactor, testing |
| [Speed up the test suite](prompts/race-speed-up-the-test-suite.md) | Race to cut the test suite's wall-clock time the most, with the same tests passing and no test removed or skipped. | testing, performance |

### Skill packs (4)

| Skill pack | What it does | Source | Tags |
|---|---|---|---|
| **AI design check** | Find and fix what makes an AI-built interface look generated: 147 rules, a checker and a fix skill. | [enmerasoftware/ai-design-check/plugin](https://github.com/enmerasoftware/ai-design-check/tree/main/plugin) | design, frontend, mobile |
| **Image skills** | Five skills for image work on a Mac: every app icon size, store screenshots, web image optimisation, screenshot diffs and SVG clean-up. | [enmerasoftware/enterm/skills/image](https://github.com/enmerasoftware/enterm/tree/main/skills/image) | image, mobile, frontend |
| **Software skills** | Six skills for everyday engineering: test-first work, root-cause debugging, code review, commit messages, release checks and a security scan. | [enmerasoftware/enterm/skills/code](https://github.com/enmerasoftware/enterm/tree/main/skills/code) | testing, debugging, review, security |
| **Video skills** | Five skills built on ffmpeg and whisper.cpp: cut and join clips, subtitles, social media formats, compression and a pre-publish check. | [enmerasoftware/enterm/skills/video](https://github.com/enmerasoftware/enterm/tree/main/skills/video) | video |

<!-- index:end -->

## Türkçe

**Enterm Kütüphanesi**, yapay zekâ kodlama ajanları için hazır istemler (prompt), yarış görevleri ve beceri paketlerinden oluşan topluluk koleksiyonudur. Claude Code, Codex, Gemini, opencode, GitHub Copilot ve Cursor ile çalışır.

- **Enterm'de kullanmak:** Enterm'deki **Kütüphane** sayfası bu deponun `index.json` dosyasını okur. Girdileri tür, etiket veya programa göre gezebilir, kaydedebilir, tek tıkla bir oturumda çalıştırabilir, yarış görevlerini bir yarışa dönüştürebilir ve beceri paketlerini ekleyebilirsin. Enterm hiçbir girdiyi tam metnini göstermeden çalıştırmaz.
- **Güvenlik:** Her girdi birleştirilmeden önce bir bakımcı tarafından incelenir; CI her alanı doğrular ve bilinen tehlikeli kalıpları reddeder. Ajanların kendi izin soruları her zaman açık kalır.
- **Katkı:** Enterm'deki Paylaş düğmesiyle gönderim formunu açabilir ya da `prompts/` altına yeni bir dosya ekleyen bir pull request gönderebilirsin. Türkçe başlık ve özet (`title_tr`, `summary_tr`) eklemen memnuniyetle karşılanır. Ayrıntılar [CONTRIBUTING.md](CONTRIBUTING.md) dosyasında.
- **Lisans:** Araçlar MIT, içerik (istemler ve açıklamalar) CC BY 4.0 lisanslıdır.

## License

- The tooling (`scripts/` and the workflow in `.github/`) is under the [MIT License](../LICENSE).
- The content (prompts, race tasks, the entries in `skills.json`, `index.json` and the documentation) is under [Creative Commons Attribution 4.0](LICENSE). Contributors keep their copyright and license their entries under CC BY 4.0 by submitting them; attribution is the `author` field and a link to this repository.
- Skill packs listed in `skills.json` live in their own repositories under their own licenses.

Enterm and this library are made by [Enmera Software](https://github.com/enmerasoftware).
