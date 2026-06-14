## App Entry & Menu Bar
- `.accessory` activation policy (no Dock icon). Settings window: temporarily switch to `.regular`, back to `.accessory` on close — required for focus.
- Settings window: manually created `NSWindow` with `NSHostingController` — `.Settings` scene doesn't work with `.accessory`.
- `AppDelegate.applicationDidFinishLaunching` eagerly inits all singletons.

## Panic Mode (`Features/PanicMode/`)
Sequence on trigger:
1. Close Notification Center (AX Escape)
2. Exit full-screen on non-safelisted apps via `AXUIElement`
3. `.hide()` all non-safelisted `NSRunningApplication`s
4. Show pre-warmed `NSVisualEffectView` blur overlays on every screen (level `.screenSaver` = 1000)
5. Mute audio; clear clipboard (toggleable)
6. 400ms later: re-hide newly-windowed apps
7. Release: `LAPolicy.deviceOwnerAuthentication`; failure → `IntruderCaptureManager`

Safelist: **transparent holes** via `CGContext` `maskImage`. Holes from `CGWindowListCopyWindowInfo`. CGEvent tap intercepts left-mouse-down to pre-apply hole before activation. Overlay backing layer is opaque black (`NSColor.black`) — `.behindWindow` blur engagement is gated by `win.isOpaque = false`, not layer alpha; opaque backing prevents bleed-through during hide() latency. Persisted as `UserDefaults["panicBlocklist"]` (JSON `[String]`).

**v0.4.0 refactor:** `PanicModeManager` reads `WorkspaceObserver.shared.runningApps` (cached) instead of `NSWorkspace.shared.runningApplications` at trigger time. During active panic, `didActivateApplicationNotification` immediately `.hide()`s non-safelisted apps (event-driven, replaces 400ms timer). A second `.cghidEventTap` (`.defaultTap`, not `.listenOnly`) consumes Cmd+Tab (keyCode 48) and Cmd+\` (keyCode 50) keyDown events while panic is active — the Dock app-switcher never receives them, preventing non-safelisted activation at the source. Both taps include a `tapDisabledByTimeout`/`tapDisabledByUserInput` watchdog that re-enables them if the kernel disables them.

## Presentation Mode (`Features/PresentationMode/`)
- `WorkspaceObserver` (Core): singleton owning all `NSWorkspace.shared.notificationCenter` subscriptions; caches `runningApps`, exposes `appLaunched`/`appTerminated`/`appActivated` subjects. No `.receive(on: DispatchQueue.main)` — NSWorkspace notifications already arrive on main thread; adding the hop causes blur-flash regression.
- `ScreenShareDetector`: polls `CGWindowListCopyWindowInfo` every 2s when watched apps are running (zero CPU at idle). Heuristics per app (Zoom, Teams, FaceTime, Loom, Chrome/Meet). Static `isSharing(bundleID:windowTitles:)` for testability. Watchlist persisted as `UserDefaults["presentationWatchlist"]` (JSON).
- `PresentationModeManager`: subscribes to `ScreenShareDetector` subjects. On share start: snapshots + hides non-safelisted apps, records `.presentationMode` history. On share stop: restores via `.unhide()`. Panic Mode takes priority (blocks engage when panic active; re-evaluates on panic release).
- `PresentationSafelist`: mirrors `AppSafelist` pattern; seeded from `panicBlocklist` on first launch. Key `"presentationSafelist"`.

## Proximity Lock (`Features/ProximityLock/`)
- `BluetoothMonitor`: `CBCentralManager` RSSI; 8s silence = absent; paired UUID in Keychain
- `LockTrigger`: Combine hysteresis; absent for N seconds → `triggerPanic()` then `lockScreen()`

## Shoulder Surfing (`Features/ShoulderSurfing/`)
- `AVCaptureSession` + `VNDetectFaceRectanglesRequest` at ~2 fps
- Credibility filter on `VNFaceObservation`: `confidence >= 0.7` AND normalized `boundingBox.width × height >= 0.02` — filters out faces on TVs, posters, mirrors
- Triggers when 2+ credible faces detected for `triggerThreshold` consecutive frames
- **False positive feedback loop (v0.5.0):** implicit signal (panic released < 5 s after auto-trigger) + explicit "Not a real threat" button in Lock History → `recordFalsePositive()` increments `SettingsStore.shoulderSurfingFalsePositiveCount`; banner in `ShoulderSurfingView` offers to lower sensitivity after 3 FPs

## Core Services
- `SettingsStore`: `@Published` + Combine `.sink` auto-persist to `UserDefaults` + `NSUbiquitousKeyValueStore`
- `CloudSyncStore`: listens for external KV changes, fans out to `SettingsStore`, `AppSafelist`, `LockHistoryStore`, `ScreenShareDetector`, `PresentationSafelist`

## History (`Features/History/`)
- `LockHistoryView.swift` — audit log UI; shows all lock events with icon, relative time, and formatted date; intruder photos as thumbnails
- `AuditSummaryGenerator.swift` — on-demand Foundation Models summary of recent lock events (macOS 26 + Apple Silicon only; `isAvailable` returns false otherwise); `generate(from:)` is `@available(macOS 26, *)`; prompt built by `buildPrompt(from:)` (internal, tested)

## State Persistence
| Data | Store |
|---|---|
| Settings | `UserDefaults` |
| Safelist | `UserDefaults["panicBlocklist"]` (JSON) |
| Lock history | `UserDefaults["lockHistory"]` (JSON) |
| BT device UUID | Keychain |
| Intruder photos | `~/Pictures/Vigil Screen Captures/<uuid>.jpg` |
| Presentation watchlist | `UserDefaults["presentationWatchlist"]` (JSON) |
| Presentation safelist | `UserDefaults["presentationSafelist"]` (JSON) |
| Shoulder surfing FP counter | `UserDefaults["shoulderSurfingFPCount"]` (device-local, not cloud) |
| Cloud sync | `NSUbiquitousKeyValueStore` |
