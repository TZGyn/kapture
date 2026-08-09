# Kapture

A native macOS menu bar app that captures a screen region, shows the screenshot
in a window, and extracts text from it on demand with on-device Vision OCR.

Press **⌘⇧S**, drag to select an area, and a window opens with your screenshot.
Click **Get Text** to recognize the text — it is copied to your clipboard and
shown alongside the image.

No network calls, no API keys — everything runs locally.

## Features

- Global hotkey **⌘⇧S** works from any app
- Region selection overlay (all screens, Escape cancels)
- The screenshot appears in a window (Screenshot / Text tabs) instead of being
  instantly OCR'd
- **Get Text** button runs on-device OCR (English, Chinese simplified/traditional,
  Japanese, Korean) and auto-copies the result to the clipboard
- **Save PNG…** keeps the screenshot without any OCR
- Open an existing image file (or drag) via the menu bar icon
- Menu bar icon with permission status

## Build & run

```bash
./build-app.sh          # produces Kapture.app
open Kapture.app        # or drag to /Applications
```

For development without the bundle:

```bash
swift run Kapture       # runs from terminal (will appear in Dock)
```

## First launch

1. Click the menu bar icon → **Grant Screen Recording Permission…**
   (required so the app can capture the screen; opening image files works
   without it).
2. Press **⌘⇧S**, drag to select a region, release — the screenshot opens in a
   window.
3. Click **Get Text** — the extracted text is copied to your clipboard and
   shown in the Text tab.

Note: macOS may require re-granting Screen Recording permission after
rebuilding the app, since the binary identity changes.

## Smoke test

```bash
swift run Kapture --test-ocr   # renders text, OCRs it, prints PASS/FAIL
```

## How it works

| Concern     | Tech |
|-------------|------|
| Hotkey      | Carbon `RegisterEventHotKey` (⌘⇧S, global) |
| Selection   | Borderless `NSPanel` overlay per screen, dim + clear-cut rectangle |
| Capture     | `CGWindowListCreateImage` (retina-aware) |
| OCR         | Vision `VNRecognizeTextRequest` (accurate, multi-language) |
| UI          | SwiftUI `MenuBarExtra` + floating result window (Screenshot/Text tabs) |

## Layout

```
Package.swift          SwiftPM manifest (macOS 13+)
build-app.sh           builds a proper .app bundle + ad-hoc codesign
Sources/Kapture/
  App.swift            app entry, menu bar UI, permission helper, OCR smoke test
  HotkeyManager.swift  global ⌘⇧S hotkey
  OverlayView.swift    selection overlay panel + drawing
  CaptureController.swift  selection flow, screen capture, coordinate mapping
  OCRService.swift     Vision text recognition
  ResultWindow.swift   floating result window (screenshot view, Get Text, Save PNG)
```
