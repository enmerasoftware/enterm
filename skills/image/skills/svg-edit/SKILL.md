---
name: svg-edit
description: Edit, clean up or optimise SVG files: change colours, size and viewBox, remove editor junk, make icons use currentColor. Use when the user works with SVG icons, logos or illustrations.
---

# SVG edit

1. Read the file. Note width, height, viewBox and fills.
2. Icons for code: remove fixed `width`/`height`, keep `viewBox`, replace solid fills with `currentColor` so the icon takes the text colour.
3. Remove editor leftovers: `<metadata>`, `sodipodi:*`, `inkscape:*`, Illustrator comments, empty groups, unused `<defs>`.
4. If `svgo` exists (`npx svgo`), run it with defaults and keep `viewBox` (`--config` with `removeViewBox: false`).
5. Never touch path data by hand unless the user asks; check the result renders by converting it once (`qlmanage -t -s 256 -o . file.svg` on macOS, or `rsvg-convert`).
6. Report the size before and after.
