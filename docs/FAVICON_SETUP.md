# Favicon Setup Guide

Modern favicon implementation following best practices for minimal file count and maximum compatibility.

## Overview

Instead of serving dozens of icon files, this setup uses just **5 icon files** and **1 manifest file** to cover all modern browsers, legacy browsers, iOS devices, and PWAs.

## Required Files

All files should be placed in `themes/[theme-name]/assets/`:

### 1. favicon.ico (32×32)
- **Format:** ICO
- **Size:** 32×32 pixels
- **Purpose:** Legacy browser support (IE, older browsers)
- **Required:** Yes

### 2. icon.svg
- **Format:** SVG (vector)
- **Purpose:** Modern browsers prefer SVG for crisp display at any size
- **Required:** Yes (highly recommended for modern browsers)

### 3. apple-touch-icon.png (180×180)
- **Format:** PNG
- **Size:** 180×180 pixels
- **Purpose:** iOS home screen icon, Safari bookmarks
- **Required:** Yes for iOS support

### 4. icon-192.png (192×192)
- **Format:** PNG
- **Size:** 192×192 pixels
- **Purpose:** PWA icon (Android, Chrome)
- **Required:** Yes for PWA support

### 5. icon-512.png (512×512)
- **Format:** PNG
- **Size:** 512×512 pixels
- **Purpose:** PWA icon (high-resolution displays)
- **Required:** Yes for PWA support

### 6. icon-mask.png (512×512 maskable)
- **Format:** PNG
- **Size:** 512×512 pixels with padding
- **Purpose:** Maskable icon for adaptive icons on Android
- **Safe zone:** 409×409 circle (20% padding on all sides)
- **Required:** Optional but recommended for PWA
- **Note:** Use [maskable.app](https://maskable.app) to verify your icon won't get clipped

### 7. manifest.webmanifest
- **Format:** JSON
- **Purpose:** Web app manifest defining PWA icons
- **Required:** Yes for PWA support

## HTML Implementation

Add these links to your `theme.liquid` file in the `<head>` section:

```liquid
<!-- Favicons -->
<link rel="icon" href="{{ 'favicon.ico' | asset_url }}" sizes="32x32">
<link rel="icon" href="{{ 'icon.svg' | asset_url }}" type="image/svg+xml">
<link rel="apple-touch-icon" href="{{ 'apple-touch-icon.png' | asset_url }}">
<link rel="manifest" href="{{ 'manifest.webmanifest' | asset_url }}">
```

## Web App Manifest

Create `manifest.webmanifest` in your assets directory:

```json
{
  "icons": [
    { "src": "/icon-192.png", "type": "image/png", "sizes": "192x192" },
    { "src": "/icon-512.png", "type": "image/png", "sizes": "512x512" },
    { "src": "/icon-mask.png", "type": "image/png", "sizes": "512x512", "purpose": "maskable" }
  ]
}
```

## Generating Icons from Source

If you have a high-resolution source image (e.g., 1024×1024), you can generate all required sizes using the following commands:

### Using sips (macOS)

```bash
cd themes/[theme-name]/assets

# Generate apple-touch-icon.png (180×180)
sips -z 180 180 icon.png --out apple-touch-icon.png

# Generate icon-192.png
sips -z 192 192 icon.png --out icon-192.png

# Generate icon-512.png
sips -z 512 512 icon.png --out icon-512.png

# Generate maskable icon with padding
sips -z 410 410 icon.png --out temp-icon.png
sips -p 512 512 temp-icon.png --padColor FFFFFF --out icon-mask.png
rm temp-icon.png
```

### Using ImageMagick (cross-platform)

```bash
cd themes/[theme-name]/assets

# Generate apple-touch-icon.png (180×180)
convert icon.png -resize 180x180 apple-touch-icon.png

# Generate icon-192.png
convert icon.png -resize 192x192 icon-192.png

# Generate icon-512.png
convert icon.png -resize 512x512 icon-512.png

# Generate maskable icon with padding
convert icon.png -resize 410x410 -background white -gravity center -extent 512x512 icon-mask.png
```

## Browser Support

| File | Browser/Platform | Notes |
|------|------------------|-------|
| `favicon.ico` | IE, old browsers | Legacy support |
| `icon.svg` | Modern browsers (Chrome, Firefox, Safari, Edge) | Preferred for crisp display |
| `apple-touch-icon.png` | iOS Safari, iOS home screen | Required for iOS devices |
| `icon-192.png` | Android Chrome, PWA | Used for PWA install |
| `icon-512.png` | Android Chrome, PWA | High-res displays |
| `icon-mask.png` | Android adaptive icons | Optional but recommended |

## Design Guidelines

### favicon.ico
- Simple, recognizable at 32×32 pixels
- High contrast
- Avoid fine details that won't be visible

### icon.svg
- Vector format ensures crisp display at any size
- Should work in both light and dark modes (or use media queries)
- Keep file size small

### apple-touch-icon.png
- 180×180 pixels (iOS automatically adds rounded corners)
- No transparency (use solid background)
- Visual margin of ~10% recommended

### Maskable Icon (icon-mask.png)
- **Critical:** Keep all important content within the 409×409 safe zone
- Use 20% padding on all sides (51px on each side for 512×512)
- Background should extend to full canvas
- Test at [maskable.app](https://maskable.app) to ensure content isn't clipped

## Verification

After implementation, verify your favicons:

1. **Browser tab:** Check if icon appears in browser tabs
2. **Bookmarks:** Add site to bookmarks and verify icon
3. **iOS home screen:** Add to iOS home screen and check icon
4. **PWA install:** Install as PWA on Android/desktop and verify all icons
5. **Maskable test:** Use [maskable.app](https://maskable.app) to verify maskable icon

## Common Issues

### Icon not updating
- Clear browser cache
- Hard refresh (Cmd+Shift+R on Mac, Ctrl+Shift+R on Windows)
- Check file paths in generated HTML

### Maskable icon getting clipped
- Ensure safe zone is 409×409 or smaller
- Add more padding to the icon
- Verify at [maskable.app](https://maskable.app)

### iOS icon not showing
- Ensure `apple-touch-icon.png` is exactly 180×180
- No transparency in the PNG
- File must be referenced in `<head>` section

## References

- [How to Favicon in 2024](https://evilmartians.com/chronicles/how-to-favicon-in-2021-six-files-that-fit-most-needs) - Original guide
- [Maskable Icons](https://web.dev/maskable-icon/) - Google's guide to maskable icons
- [Web App Manifest](https://developer.mozilla.org/en-US/docs/Web/Manifest) - MDN documentation
