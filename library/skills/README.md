# Skill packs

A skill pack is a [Claude Code plugin](https://docs.claude.com/en/docs/claude-code/plugins): a folder with `.claude-plugin/plugin.json` and one or more `skills/<name>/SKILL.md` files. Each skill is a short set of instructions an agent follows when the task fits, or when you call it by name (`/<pack>:<skill>`).

This library does not copy skill packs. It lists them in [`../skills.json`](../skills.json), each pointing at a repository, a folder and a ref. The code stays where its author maintains it, under its own license, and Enterm fetches it from there.

## How Enterm uses an entry

1. On the Library page you choose **Add skill**. Enterm shows the repository, path and ref, with a link to the source.
2. After you confirm, it fetches that folder at that ref and adds it to your preset packs.
3. New sessions load the pack with `--plugin-dir`. Nothing is written to `~/.claude`, and you can turn the pack off in Settings at any time.

Without Enterm, clone the repository and run `claude --plugin-dir <repo>/<path>`.

## Entry format

```json
{
  "id": "ai-design-check",
  "title": "AI design check",
  "summary": "Find and fix what makes an AI-built interface look generated: 147 rules, a checker and a fix skill.",
  "repo": "enmerasoftware/ai-design-check",
  "path": "plugin",
  "ref": "main",
  "programs": ["claude", "codex"],
  "tags": ["design", "frontend", "mobile"],
  "author": "enmerasoftware",
  "title_tr": "Yapay zekâ tasarım kontrolü",
  "summary_tr": "Yapay zekâyla yapılmış bir arayüzü üretilmiş gösteren şeyleri bulur ve düzeltir: 147 kural, bir denetleyici ve bir düzeltme becerisi."
}
```

| Field | Required | Rules |
|---|---|---|
| `id` | yes | Lowercase slug, unique across the whole library (prompts included) |
| `title` | yes | Sentence case, at most 60 characters, no full stop |
| `summary` | yes | One sentence ending with a full stop |
| `repo` | yes | `owner/name` of a public GitHub repository |
| `path` | yes | The folder holding `.claude-plugin/plugin.json`, relative to the repository root; `.` for the root |
| `ref` | yes | A tag, commit or branch. Tags and commits are preferred: a branch can change after review |
| `programs` | yes | The programs it is known to work with: `claude`, `codex`, `gemini`, `opencode`, `copilot`, `cursor` |
| `tags` | yes | One to four tags from [`TAGS.md`](../TAGS.md) |
| `author` | yes | The GitHub handle of the person or organisation that maintains the pack |
| `title_tr`, `summary_tr` | no | Turkish title and summary, both or neither |

## Adding a pack

Open a pull request that adds an entry to `skills.json` and runs `node scripts/build-index.mjs`, or use the [skill submission form](https://github.com/enmerasoftware/enterm/issues/new?template=submit-skill.yml). Before merging, a maintainer reads the whole pack against the [review checklist](../CONTRIBUTING.md#review-checklist): readable source, a permissive license, no secrets, and no network calls hidden in scripts.

When a listed pack changes, the entry's `ref` is updated by pull request, and the new version is reviewed the same way.
