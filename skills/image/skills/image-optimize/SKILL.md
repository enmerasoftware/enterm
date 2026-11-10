---
name: image-optimize
description: Shrink images for the web or apps: resize, convert to WebP or AVIF, strip metadata, keep quality. Use when images are too large, a page is slow, or the user asks to optimise or convert images.
---

# Optimise images

Tools, checked in this order: `cwebp`/`avifenc` (brew install webp libavif), ImageMagick `magick`, macOS `sips`. Say which one you use.

1. Never overwrite originals: write into an `optimized/` folder next to them.
2. Resize to the largest size actually shown (for web, 2x the CSS width; 2400 px wide is plenty for a full-width hero).
3. Photos: WebP quality 80 (`cwebp -q 80 in.jpg -o out.webp`) or AVIF (`avifenc --min 20 --max 30 in.jpg out.avif`). Keep a JPEG fallback (`magick in.jpg -strip -quality 82 -sampling-factor 4:2:0 out.jpg`) if old browsers matter.
4. Graphics with flat colour or transparency: PNG through `pngquant` if available, or lossless WebP.
5. Strip EXIF and GPS data unless the user needs it.
6. Report a table: file, old size, new size, saving. Mention the `<picture>` markup if formats changed.
