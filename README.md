# NeekShot

Native macOS menu bar screenshot utility focused on silent, non-blocking capture.

The first version captures the main display from a global hotkey, saves a PNG to `~/Pictures/NeekShot`, copies it to the clipboard, and avoids opening a capture overlay or editor.

## Why

macOS and existing screenshot apps already handle many capture workflows well, especially region selection, annotations, scrolling capture, and sharing. NeekShot is intentionally narrower: capture without pulling focus when you are already doing something else.

## Market Gap

This should not try to be a generic screenshot replacement. The useful gap is stricter:

1. Press one shortcut.
2. Do not switch focus.
3. Do not show an overlay.
4. Save and copy in the background.
5. Surface only minimal status.

Existing tools cover adjacent workflows:

- Apple Screenshot already supports full-screen keyboard capture, desktop save, clipboard save, screenshot timers, and optional floating thumbnails. Region and window capture still involve selection UI.
- CleanShot X is a strong paid replacement with a Quick Access overlay, fullscreen/window/area/scrolling capture, annotation, floating screenshots, capture history, and cloud sharing.
- Shottr is the closest competitor because it is fast, native, scriptable, and supports copy/save workflows, repeat area capture, and Raycast/Alfred integration. It still centers around preview/editor and selection workflows.
- Snagit is a mature capture/editor/sharing suite.
- Xnapper focuses on polished, presentable screenshots.
- Raycast and Alfred can provide global hotkey plumbing, but they are action wrappers rather than dedicated silent screenshot products.

## MVP Scope

- Menu bar only app
- Global hotkey: `Control + Option + Command + S`
- Silent main-display screenshot
- Auto-save to `~/Pictures/NeekShot`
- Auto-copy to clipboard
- Permission helper for macOS Screen Recording access
- No cloud upload
- No editor
- No history by default

## Requirements

- macOS 14 or newer
- Xcode command line tools or Xcode
- Swift 6-compatible toolchain

## Run From Source

```bash
swift run NeekShot
```

The app appears in the menu bar. Use the menu item or press `Control + Option + Command + S`.

## Build an App Bundle

```bash
./scripts/build-app.sh
open .build/app/NeekShot.app
```

The bundle is unsigned for now. A signed and notarized app should be added before public binary releases.

## Permission Notes

macOS requires screen recording permission for apps that capture screen contents. If capture fails, use the menu item to request permission or open System Settings. You may need to quit and reopen the app after granting access.

## Current Limitations

- Captures the main display only.
- The hotkey is fixed.
- There is no region selection yet.
- There is no signed release build yet.
- Some DRM or protected content may not appear in screenshots.
