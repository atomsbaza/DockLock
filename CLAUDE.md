# DockLock (VigilScreen)

macOS menu bar privacy app (Swift 6, SwiftUI, AppKit). Features: Panic Mode (⌘⇧L instant blur + hide), Proximity Lock (Bluetooth range), Shoulder Surfing Detection (Vision + camera).

- **Target**: macOS 15+, Xcode 16+, Swift 6.0
- **Bundle ID**: `com.pisit.koolplukpol.VigilScreen` / Team: `VPTPA7XM79`
- **Deps**: Zero — pure Apple frameworks

## Commands
```bash
open VigilScreen.xcodeproj
xcodebuild -scheme VigilScreen -configuration Debug build
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/AppBlocklistTests
```

## Structure
```
VigilScreen/App/, MenuBar/, Features/PanicMode/, Features/ProximityLock/,
Features/ShoulderSurfing/, Features/History/, Core/, Settings/, Resources/
VigilScreenTests/   — 39 tests
.claude/agents/     — swift-reviewer, ui-reviewer, xcode-build
.claude/commands/   — /version-bump, /release, /pr-preflight
```

## Context Files
Read `.claude/rules/architecture.md` for feature internals and state persistence.
Read `.claude/rules/conventions.md` for Swift 6 rules, coding conventions, and test coverage.
