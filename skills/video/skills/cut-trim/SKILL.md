---
name: cut-trim
description: Cut, trim or join video clips with ffmpeg without re-encoding when possible. Use when the user wants a part of a video, to remove a section, or to join several clips.
---

# Cut, trim, join

Check `ffmpeg -version` first; if it is missing, say `brew install ffmpeg` and stop. Never overwrite the source: write next to it with a suffix. Pass `-threads 4` so the machine stays usable.

1. Read the input with `ffprobe -v error -show_entries format=duration:stream=codec_name,width,height,r_frame_rate -of json <file>` and say what it is.
2. Ask for start and end only if the user gave none. Accept `mm:ss` or seconds.
3. Fast cut (keyframe-accurate, no quality loss): `ffmpeg -ss <start> -to <end> -i in.mp4 -c copy out.mp4`.
4. Frame-accurate cut, when the user needs the exact frame: `ffmpeg -i in.mp4 -ss <start> -to <end> -c:v libx264 -crf 18 -preset medium -c:a aac -b:a 192k out.mp4`.
5. Join clips with the same codec: write `list.txt` with `file 'a.mp4'` lines, then `ffmpeg -f concat -safe 0 -i list.txt -c copy joined.mp4`. Different codecs: re-encode each to the same settings first.
6. Check the result with `ffprobe` (duration matches) and report the output path and size.
