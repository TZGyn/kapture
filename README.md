# Kapture

A native macOS menu bar app that captures a screen region and extracts the text
from it using on-device Vision OCR. Press **⌘⇧S**, drag to select an area, and
the recognized text is copied to your clipboard and shown in a floating window.

No network calls, no API keys — everything runs locally.

## Features

- Global hotkey **⌘⇧S** works from any app
- Region selection overlay (all screens, Escape cancels)
- OCR for English, Chinese (simplified/traditional), Japanese, Korean
- Text is auto-copied to the clipboard and shown in a floating window
- Extract text from an existing image file via the menu bar icon
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
   (required so the app can capture the screen; text extraction from files
   works without it).
2. Press **⌘⇧S**, drag to select a region, release.
3. The extracted text lands on your clipboard and in the result window.

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
| UI          | SwiftUI `MenuBarExtra` + floating result window |

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
  ResultWindow.swift   floating result window + image-file extraction
```
