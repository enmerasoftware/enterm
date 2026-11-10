---
name: screenshot-diff
description: Compare two screenshots or images and show what changed, as a highlighted diff and a percentage. Use when checking a UI change, a visual regression, or whether two images are the same.
---

# Screenshot diff

1. Both images must have the same pixel size; check with `sips -g pixelWidth -g pixelHeight`. If not, say so and offer to crop or pad, never stretch.
2. With ImageMagick: `magick compare -metric AE -fuzz 2% a.png b.png diff.png` prints the number of different pixels and writes a red-highlighted diff. Divide by width x height for a percentage.
3. Without ImageMagick, use a short Python script with Pillow if it is installed (`ImageChops.difference`, then `getbbox()` for the changed area).
4. Report the percentage, the bounding box of the change, and open or show `diff.png`. Describe in words what changed when you can see it.
