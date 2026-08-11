# AGENTS.md

Kapture is a native macOS menu-bar screenshot + OCR app written in Swift/SwiftUI.
Single executable SwiftPM package, no external dependencies (all Apple frameworks).

## Architecture

Control flow for the main path: menu bar → hotkey → overlay → capture → result window → OCR.

- `Sources/Kapture/App.swift` — `@main` entry. `MenuBarExtra` menu, `AppDelegate`
  (wires hotkey → `CaptureController.begin()`; handles `--test-ocr`), `PermissionManager`
  (wraps `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`).
- `Sources/Kapture/HotkeyManager.swift` — Carbon `RegisterEventHotKey`, hardcoded
  ⌘⇧S (`kVK_ANSI_S`, `cmdKey | shiftKey`), signature `0x4B505452`.
- `Sources/Kapture/CaptureController.swift` — selection flow. Creates one borderless
  `NSPanel` overlay per screen, then captures via `ScreenCapture` and hands the image
  to `ResultWindow`. Coordination happens in `begin()`/`finishSelection()`/`cancelSelection()`.
- `Sources/Kapture/ScreenCapture` (same file) — macOS 14+: ScreenCaptureKit
  `SCScreenshotManager` + manual pixel-space crop (`display.width / display.frame.width`
  scale); macOS 13: `CGWindowListCreateImage` fallback.
- `Sources/Kapture/OverlayView.swift` — `NSPanel` + `NSView` drawing overlay; mouse-driven
  rect selection (min 2×2 pt), Escape (keyCode 53) cancels; selection committed via
  `window.convertToScreen` (screen coordinates).
- `Sources/Kapture/OCRService.swift` — Vision `VNRecognizeTextRequest`, `.accurate`
  level, languages `["en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"]`. Custom
  line-order sort: observations sorted top→bottom by `boundingBox.midY` (tolerance
  `0.02`), then left→right. Runs on a private serial `DispatchQueue`
  (`dev.tzgyn.kapture.ocr`), completes on that queue — callers must hop back to main.
- `Sources/Kapture/ResultWindow.swift` — `ResultWindow.show(image:)` (single shared
  floating window, closes previous), `CaptureModel` (ObservableObject, `@Published`
  `mode` = screenshot/text), `ResultView` (SwiftUI, Screenshot/Text tabs, Get Text /
  Save PNG / Copy Text).

Singletons everywhere: `HotkeyManager.shared`, `CaptureController.shared`,
`ScreenCapture.shared`, `OCRService.shared`, `ResultWindow.shared`.

Note: packaging references `dev.tzgyn.kapture` as the bundle identifier — match this
in any new code (queue labels, TCC/plist references).

## Commands

```bash
swift build                  # debug build (also: swift run Kapture)
swift build -c release       # release build (what build-app.sh uses)
swift run Kapture            # dev run from terminal (app appears in Dock)
swift run Kapture --test-ocr # OCR smoke test: renders text, OCRs it, prints PASS/FAIL, exit 0/1
./build-app.sh               # release build + Kapture.app bundle + icon + ad-hoc codesign
./release.sh <version>       # e.g. ./release.sh 1.0.1: builds app, zips to dist/Kapture.zip, prints sha256
scripts/make-icon.sh         # regenerates Kapture.app/Contents/Resources/Icon.icns from scripts/gen-icon.swift
```

There is no test target and no linter/formatter configured. Verification = build +
`--test-ocr`.

## Bundle build & signing

`build-app.sh` does: release build → handwritten `Info.plist` (NOT generated from
`Package.swift`) → `make-icon.sh` → `codesign` with self-signed identity `kapture-dev`
stored in a dedicated keychain at `~/.config/kapture/signing.keychain-db` (not the
login keychain). Honest bugs to keep in mind:

- Uses `security create-keychain`/`unlock-keychain` with a hardcoded password
  (`kapture-dev`) — if the cert creation fails midway, the keychain may be left in an
  undefined state; the script is mostly idempotent but re-run it before assuming failure.
- The self-signed cert is created with Homebrew OpenSSL (`/opt/homebrew/bin/openssl`,
  falls back to `/usr/local/bin/openssl`, then system `openssl`) and imported as a
  pkcs12 (`-export -legacy`). The legacy flag is important — modern OpenSSL defaults
  to formats the macOS `security` tool rejects.
- `LSUIElement` = true → no Dock icon. Info.plist also hardcodes
  `CFBundleShortVersionString` 1.0 / `CFBundleVersion` 1 — bump here for releases,
  and match it in `release.sh` args.

macOS may require re-granting Screen Recording permission when the binary identity
changes (TCC tracks the binary, not the source).

## Release process

1. `./release.sh <version>` — builds, zips `Kapture.app` to `dist/Kapture.zip`,
   prints its sha256 (that's all it does, it does not tag or upload).
2. Tag `git tag v<version> && git push origin v<version>` and attach the zip to a
   GitHub release manually (the old `.github/workflows/release.yml` was removed;
   `release.sh` output still says the workflow will upload the zip, which is stale).
3. The Homebrew cask lives in `TZGyn/homebrew-tap` — bump `version` and `sha256`
   there for each release.

Icon note: the cask references the `Icon.icns` built into the app bundle, so no
separate icon release step needed.

## Gotchas

- Coordinate spaces differ: overlay selections are in global screen points
  (via `convertToScreen`), ScreenCaptureKit images are in pixels and the crop must
  scale by `display.width / display.frame.width`. Don't mix them.
- Starting on macOS 13 vs 14 changes the capture path: 13 uses the `CGWindowListCreateImage`
  fallback, which only handles the primary screen (`frame.origin == .zero`) and
  needs explicit Y-flip (`primary.frame.height - rect.maxY`). Get selection rect
  handling wrong on one path and you break only one OS version — test on both.
- When selection overlays are active for more than one screen macOS may also be
  capturing the overlay panels themselves while the selection is running; the overlay
  windows' `windowNumber` IDs are collected in `begin()` and excluded via
  `SCContentFilter(excludingWindows:)` when capturing. If you add any new window that
  shows during overlay/selection, add it to the exclusion set.
- The OCR completion runs on a background queue — never touch `CaptureModel`/UI from
  it; `runOCR` hops to `@MainActor` via `Task { @MainActor in ... }`.
- `--test-ocr` is processed in `AppDelegate.applicationDidFinishLaunching` and must
  `exit()` with 0/1 inside the completion; the `RunLoop.main.run()` after is what keeps
  the process alive until the async OCR finishes. If OCR returns empty text it
  doesn't crash — just prints FAIL.
- No `@MainActor` annotations on AppDelegate / HotkeyManager; keep new code on main
  thread for AppKit calls.
- `.gitignore` covers `.build/`, `Kapture.app/`, `dist/` — build artifacts should
  never be committed.
