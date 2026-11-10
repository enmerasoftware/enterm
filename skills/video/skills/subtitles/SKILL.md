---
name: subtitles
description: Create Turkish or English subtitles for a video with whisper.cpp, then attach or burn them in with ffmpeg. Use when the user wants subtitles, captions, an SRT file or a transcript of a video.
---

# Subtitles

Check `ffmpeg -version` first; if it is missing, say `brew install ffmpeg` and stop. Never overwrite the source: write next to it with a suffix. Pass `-threads 4` so the machine stays usable.

1. Find whisper: `whisper-cli` on PATH, or Enterm's copy at `/Applications/Enterm.app/Contents/MacOS/whisper-cli`. Without it, offer `brew install whisper-cpp`.
2. Models live in `~/Library/Application Support/Enterm/whisper` when Enterm downloaded them; otherwise ask which model file to use. Prefer `small` or larger for Turkish.
3. Extract audio: `ffmpeg -i in.mp4 -ar 16000 -ac 1 -c:a pcm_s16le audio.wav`.
4. Transcribe: `whisper-cli -m <model> -l tr -osrt -of out audio.wav` (use `-l en` for English, `-l auto` if unsure).
5. Read the SRT and fix obvious errors in names and technical words the user mentioned. Keep lines under 42 characters, two lines at most.
6. Soft subtitles (switchable): `ffmpeg -i in.mp4 -i out.srt -c copy -c:s mov_text -metadata:s:s:0 language=tur out-sub.mp4`.
7. Burned in (for social media): `ffmpeg -i in.mp4 -vf "subtitles=out.srt:force_style='FontName=Helvetica,FontSize=18,Outline=2'" -c:a copy out-burned.mp4`.
8. Delete `audio.wav` at the end and report the files.
