# DockLock (VigilScreen)

macOS menu bar privacy app (Swift 6, SwiftUI, AppKit). Features: Panic Mode (⌘⇧L instant blur + hide), Proximity Lock (Bluetooth range), Shoulder Surfing Detection (Vision + camera), Presentation Mode (auto-hide apps when screen sharing detected).

- **Target**: macOS 15+, Xcode 16+, Swift 6.0
- **Bundle ID**: `com.pisit.koolplukpol.VigilScreen` / Team: `VPTPA7XM79`
- **Deps**: Zero — pure Apple frameworks

## Commands
```bash
open VigilScreen.xcodeproj
xcodebuild -scheme VigilScreen -configuration Debug build
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test
xcodebuild -scheme VigilScreen -destination 'platform=macOS' test -only-testing:VigilScreenTests/AppBlocklistTests
```

## Structure
```
VigilScreen/App/, MenuBar/, Features/PanicMode/, Features/ProximityLock/,
Features/ShoulderSurfing/, Features/PresentationMode/, Features/History/,
Core/, Settings/, Resources/
VigilScreenTests/   — 132 tests
.claude/rules/      — architecture.md, conventions.md
.claude/commands/   — /version-bump, /release, /pr-preflight
```

## Context Files
Read `.claude/rules/architecture.md` for feature internals and state persistence.
Read `.claude/rules/conventions.md` for Swift 6 rules, coding conventions, and test coverage.
