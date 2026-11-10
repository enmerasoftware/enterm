---
name: compress
description: Make a video smaller for sharing, WhatsApp, email or the web while keeping it watchable. Use when a video file is too large or the user wants a target size.
---

# Compress

Check `ffmpeg -version` first; if it is missing, say `brew install ffmpeg` and stop. Never overwrite the source: write next to it with a suffix. Pass `-threads 4` so the machine stays usable.

1. Read duration and size with `ffprobe`.
2. Quality target (default): `ffmpeg -i in.mp4 -c:v libx264 -crf 26 -preset slow -c:a aac -b:a 128k -movflags +faststart out-small.mp4`. Add `-vf scale=-2:1080` if the source is larger than 1080p.
3. Size target: bitrate (kbit/s) = target MB x 8192 / seconds - 128 for audio. Run two-pass: first `-pass 1 -an -f null /dev/null`, then `-pass 2` with the audio. Remove the `ffmpeg2pass*` files afterwards.
4. HEVC halves the size on Apple devices (`-c:v libx265 -crf 28 -tag:v hvc1`) but older Android and some web players do not play it. Ask before using it.
5. Report old size, new size and the ratio.
