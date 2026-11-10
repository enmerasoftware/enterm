# Enterm preset skills

Each folder is one pack. A pack is a Claude Code plugin: `.claude-plugin/plugin.json` plus `skills/<name>/SKILL.md`. Turn packs on in Enterm under Settings → Hazır Beceriler; new sessions load them with `--plugin-dir`, nothing is written to `~/.claude`. In a session a skill runs by itself when it fits, or by name: `/<pack>:<skill>`.

To use a pack without Enterm: `claude --plugin-dir skills/video`.


## Video (`video`)

Cutting, subtitles, social formats and checks for video files with ffmpeg and whisper.cpp.

- `/video:cut-trim`: Cut, trim or join video clips with ffmpeg without re-encoding when possible.
- `/video:subtitles`: Create Turkish or English subtitles for a video with whisper.cpp, then attach or burn them in with ffmpeg.
- `/video:social-formats`: Turn a video into vertical 9:16, square 1:1 or horizontal 16:9 versions for Reels, Shorts, TikTok and YouTube.
- `/video:video-check`: Check a finished video before publishing: resolution, frame rate, loudness, black frames, silence and file size.
- `/video:compress`: Make a video smaller for sharing, WhatsApp, email or the web while keeping it watchable.

## Software (`code`)

Test-first work, debugging, review, commit messages, release and security checks.

- `/code:tdd`: Work test-first: write a failing test, make it pass with the smallest change, then clean up.
- `/code:debug`: Find the cause of a bug before changing code: reproduce, narrow down, prove, then fix.
- `/code:review`: Review a diff or branch for real defects: wrong behaviour, crashes, security holes, data loss, missing edge cases.
- `/code:commit-message`: Write a clear commit message for the staged changes.
- `/code:release-check`: Check that a project is ready to release: tests, version number, changelog, build, uncommitted files and tags. Use before tagging, publishing or shipping a version..
- `/code:security-scan`: Scan a codebase or a change for common security problems: secrets, injection, unsafe deserialisation, weak crypto, permissive CORS, vulnerable dependencies.

## Image (`image`)

App icons, store screenshots, image optimisation, screenshot comparison and SVG edits.

- `/image:app-icon`: Produce every app icon size from one square source image for iOS, macOS, Android, favicons and PWA.
- `/image:store-screenshots`: Prepare App Store and Google Play screenshots at the exact required sizes, with optional captions and device background.
- `/image:image-optimize`: Shrink images for the web or apps: resize, convert to WebP or AVIF, strip metadata, keep quality.
- `/image:screenshot-diff`: Compare two screenshots or images and show what changed, as a highlighted diff and a percentage.
- `/image:svg-edit`: Edit, clean up or optimise SVG files: change colours, size and viewBox, remove editor junk, make icons use currentColor.


Contributing a skill: see `CONTRIBUTING.md`.
