---
name: app-icon
description: Produce every app icon size from one square source image for iOS, macOS, Android, favicons and PWA. Use when the user has an icon or logo and needs it in the sizes a platform asks for.
---

# App icon

Tools: `sips` (built into macOS) for resizing, `iconutil` for `.icns`. ImageMagick (`magick`) is optional.

1. Check the source: square, at least 1024x1024, PNG. If it is smaller, say the result will be soft.
2. iOS (Xcode 15+): one 1024x1024 PNG without transparency in `AppIcon.appiconset` is enough. Flatten alpha onto the background colour if needed.
3. macOS `.icns`: make `icon.iconset` with 16, 32, 128, 256, 512 and their @2x (`sips -z <n> <n> src.png --out icon.iconset/icon_<n>x<n>.png`, @2x named `icon_<n>x<n>@2x.png`), then `iconutil -c icns icon.iconset`.
4. Android: 48, 72, 96, 144, 192 px into `mipmap-mdpi` .. `mipmap-xxxhdpi`, plus a 512 px Play Store icon.
5. Web: `favicon.ico` (16, 32, 48), `apple-touch-icon.png` 180, PWA 192 and 512, and the matching `<link>` and manifest lines.
6. List every file written.
