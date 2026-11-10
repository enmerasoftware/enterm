---
name: video-check
description: Check a finished video before publishing: resolution, frame rate, loudness, black frames, silence and file size. Use when the user asks whether a video is ready, or after rendering one.
---

# Video check

Check `ffmpeg -version` first; if it is missing, say `brew install ffmpeg` and stop. Never overwrite the source: write next to it with a suffix. Pass `-threads 4` so the machine stays usable.

Run each check and report a short table: check, value, ok or not.

1. Format: `ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,pix_fmt -of compact <file>`. Expect H.264 or HEVC, `yuv420p` for wide playback.
2. Loudness: `ffmpeg -i <file> -af loudnorm=print_format=summary -f null -`. Social and YouTube aim near -14 LUFS, true peak under -1 dBTP.
3. Black frames: `ffmpeg -i <file> -vf blackdetect=d=0.5:pix_th=0.1 -an -f null -` and list the times.
4. Silence: `ffmpeg -i <file> -af silencedetect=n=-45dB:d=1.5 -f null -` and list the times.
5. Faststart for web: check that `moov` is at the start (`ffprobe -v trace <file> 2>&1 | grep -m1 -E "type:'(moov|mdat)'"` shows moov first).
6. If loudness is off, offer the two-pass loudnorm fix; do not change the file without asking.
