# AGENTS.md

Guidance for Codex and other coding agents working in this repository.

## Project Overview

Vigil Screen is a macOS menu bar app built with Swift 6, SwiftUI, and AppKit.
It provides privacy protection through:

- Panic Mode: blur all screens and hide non-safelisted apps with the global hotkey `Command+Shift+L`
- Proximity Lock: automatically lock when a paired Bluetooth device moves out of range
- Shoulder Surfing Detection: trigger Panic Mode when another face is detected locally by the camera
- Lock History: local audit trail for lock and panic events

Target platform:

- macOS 15 Sequoia or later
- Xcode 16 or later
- Swift 6.0 or later

Dependencies:

- No third-party packages
- Apple frameworks only, including SwiftUI, AppKit, CoreBluetooth, AVFoundation, Vision, LocalAuthentication, Combine, and Security

## Build And Test Commands

Open the project in Xcode:

```bash
open VigilScreen.xcodeproj
```

Build from the command line:

```bash
xcodebuild -scheme VigilScreen -configuration Debug build
```

Run all tests:

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test
```

Run a single test class:

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/AppBlocklistTests
```

## Repository Layout

```text
VigilScreen/
├── App/
│   ├── DockLockApp.swift
│   └── AppDelegate.swift
├── MenuBar/
│   ├── MenuBarManager.swift
│   ├── MenuBarView.swift
│   └── WelcomeView.swift
├── Features/
│   ├── PanicMode/
│   ├── ProximityLock/
│   ├── ShoulderSurfing/
│   └── History/
├── Core/
├── Settings/
└── Resources/

VigilScreenTests/
```

## Architecture Notes

### App Entry And Menu Bar

- `VigilScreen/App/DockLockApp.swift` contains the `@main` SwiftUI app.
- `VigilScreen/App/AppDelegate.swift` owns app lifecycle, `.accessory` activation policy, menu bar startup, settings window management, and global hotkey registration.
- `VigilScreen/MenuBar/MenuBarManager.swift` owns the `NSStatusItem` and `NSPopover`.
- The app does not use normal SwiftUI window scenes. Settings are shown through a manually managed `NSWindow` because the app is menu-bar only.

### Panic Mode

Main files:

- `VigilScreen/Features/PanicMode/PanicModeManager.swift`
- `VigilScreen/Features/PanicMode/AppBlocklist.swift`
- `VigilScreen/Features/PanicMode/PanicModeView.swift`

Behavior:

- Hide non-safelisted apps.
- Keep safelisted apps visible and interactive.
- Show blur overlays across all screens.
- Release can require LocalAuthentication.
- Failed release attempts may trigger intruder capture.
- Panic Mode also handles privacy actions such as clipboard clearing and audio mute where implemented.

### Proximity Lock

Main files:

- `VigilScreen/Features/ProximityLock/BluetoothMonitor.swift`
- `VigilScreen/Features/ProximityLock/LockTrigger.swift`
- `VigilScreen/Features/ProximityLock/ProximityView.swift`

Behavior:

- `BluetoothMonitor` scans nearby devices and tracks paired-device presence/RSSI.
- `LockTrigger` applies hysteresis and countdown logic before locking.
- Proximity lock triggers Panic Mode before locking the screen.

### Shoulder Surfing

Main files:

- `VigilScreen/Features/ShoulderSurfing/ShoulderSurfingDetector.swift`
- `VigilScreen/Features/ShoulderSurfing/ShoulderSurfingView.swift`

Behavior:

- Uses local Vision and AVFoundation camera processing.
- Can trigger Panic Mode when an additional face is detected for the configured duration.
- Can auto-release when the threat clears, depending on settings.

### Core Services

- `VigilScreen/Core/SettingsStore.swift`: `UserDefaults`-backed app settings.
- `VigilScreen/Core/PermissionManager.swift`: permission checks and prompts.
- `VigilScreen/Core/LockEngine.swift`: screen lock implementation.
- `VigilScreen/Core/LockHistoryStore.swift`: persisted local lock event history.
- `VigilScreen/Core/IntruderCaptureManager.swift`: front-camera capture after failed authentication.
- `VigilScreen/Core/CloudSyncStore.swift`: iCloud key-value sync coordination.

## Persistence

- Settings: `UserDefaults`
- App safelist: JSON in `UserDefaults`
- Lock history: JSON in `UserDefaults`
- Paired Bluetooth device UUID: Keychain
- Intruder capture photos: `~/Pictures/Vigil Screen Captures/`
- Cloud sync, where enabled: `NSUbiquitousKeyValueStore`

## Swift And Concurrency Rules

- Keep Swift 6 strict concurrency in mind for all changes.
- Use `@MainActor` for code touching AppKit, SwiftUI state, `NSApplication`, windows, status items, popovers, and UI-bound managers.
- Be careful when crossing actor boundaries from delegate callbacks such as CoreBluetooth, AVFoundation, Vision, and event monitors.
- Prefer existing Combine-based observation patterns already used in the project.
- Add `Sendable` conformance only when it is semantically correct.

## Development Guidelines

- Follow the existing file organization and naming conventions.
- Keep changes scoped to the requested feature or bug.
- Avoid introducing third-party dependencies unless explicitly requested.
- Prefer native Apple APIs and existing project helpers.
- Do not rewrite unrelated architecture while making a focused change.
- Preserve local-first privacy behavior. Do not add telemetry, analytics, or network calls without explicit direction.
- For UI work, match the existing macOS SwiftUI/AppKit style and keep the menu-bar app model intact.
- Treat permission-sensitive flows carefully: Accessibility, Bluetooth, Camera, LocalAuthentication, Keychain, and iCloud.

## Design Specs

- Design specs for new features live in `docs/superpowers/specs/`, one Markdown file per feature.
- Every spec ships a companion workflow page: an HTML file at the same path with a `.html` extension instead of `.md`.
- The companion page is a visual walkthrough of the new feature's workflow, shown in the context of the app's existing triggers (Panic Mode, Proximity Lock, Shoulder Surfing, Presentation Mode), not just the new feature in isolation.
- The HTML must be self-contained: inline CSS only, no external stylesheets, fonts, or CDN scripts, and no other external assets.
- Self-containment is required so the page renders correctly both when opened locally from disk and when published elsewhere.

## Testing Guidance

Run relevant tests after changes when possible.

Existing test coverage includes:

- App safelist persistence and CRUD
- Settings defaults, clamping, and round trips
- Bluetooth discovered-device signal classification
- Lock trigger countdown behavior
- Bluetooth monitor scan and pairing state
- Panic mode manager behavior where unit-testable

Some behavior requires real hardware or OS integration and is not fully unit-testable:

- Real Bluetooth scanning
- Actual screen lock
- Touch ID, password, or Apple Watch authentication
- Camera capture
- `NSApplication.hide()`
- Accessibility interactions with other apps and full-screen Spaces

When tests cannot cover an OS-integrated behavior, document the manual verification needed.

## Git And Workspace Safety

- The working tree may contain user changes. Do not revert unrelated edits.
- Check `git status --short` before and after substantial work.
- Do not run destructive git commands unless explicitly requested.
- Keep generated files and Xcode user state out of commits unless they are intentionally part of the change.


## Codex-converted Claude guidance

- Converted skills, agent roles, and command workflows are in `.agents/skills/`.

- Project rules copied from Claude are in `.agents/rules/`; read the relevant files before changing related code.

- Claude permissions, model selections, hooks, and slash-command registration are not used; follow Codex approval and tool instructions.

