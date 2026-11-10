---
name: store-screenshots
description: Prepare App Store and Google Play screenshots at the exact required sizes, with optional captions and device background. Use when the user is preparing store listing images.
---

# Store screenshots

1. Required sizes (portrait): iPhone 6.9" 1320x2868 (or 1290x2796), iPad 13" 2064x2752. Google Play phone: 1080x1920 or larger, 16:9 or 9:16, under 8 MB, PNG or JPEG.
2. Take screenshots from the simulator at the right device: `xcrun simctl io booted screenshot shot.png`. Set a clean status bar first: `xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4`.
3. Resize only when the aspect ratio already matches: `sips -z <h> <w> in.png --out out.png`. Never stretch; pad instead.
4. Captions: if the user wants text above the device, compose with ImageMagick (`magick -size WxH canvas:'#hex' ... -annotate`) or an HTML page rendered by the browser. Keep text large: at least 70 px at these sizes.
5. Check each file's pixel size with `sips -g pixelWidth -g pixelHeight` and list them by device.
