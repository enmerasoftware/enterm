---
name: social-formats
description: Turn a video into vertical 9:16, square 1:1 or horizontal 16:9 versions for Reels, Shorts, TikTok and YouTube. Use when the user wants a video resized, reframed or prepared for a social platform.
---

# Social formats

Check `ffmpeg -version` first; if it is missing, say `brew install ffmpeg` and stop. Never overwrite the source: write next to it with a suffix. Pass `-threads 4` so the machine stays usable.

Targets: Reels, Shorts, TikTok 1080x1920 (9:16); feed 1080x1080 (1:1) or 1080x1350 (4:5); YouTube 1920x1080 (16:9). H.264, AAC, `-movflags +faststart`.

1. Read the size with `ffprobe`.
2. Ask whether to crop (fills the frame, loses the sides) or pad (keeps everything, adds a blurred background). Default to the blurred background for talking heads with text, crop otherwise.
3. Crop to 9:16 from the centre: `ffmpeg -i in.mp4 -vf "crop=ih*9/16:ih,scale=1080:1920" -c:v libx264 -crf 20 -c:a aac -movflags +faststart out-9x16.mp4`.
4. Blurred background: `ffmpeg -i in.mp4 -filter_complex "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=20[bg];[0:v]scale=1080:-2[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2" -c:v libx264 -crf 20 -c:a aac -movflags +faststart out-9x16.mp4`.
5. Keep platform limits in mind: Reels up to 90 s for most reach, Shorts up to 3 minutes. Say so if the clip is longer.
6. Report each file with its size and duration.
