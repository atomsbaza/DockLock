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

Safelist: **transparent holes** via `CGContext` `maskImage`. Holes from `CGWindowListCopyWindowInfo`. CGEvent tap intercepts left-mouse-down to pre-apply hole before activation. Persisted as `UserDefaults["panicBlocklist"]` (JSON `[String]`).

## Proximity Lock (`Features/ProximityLock/`)
- `BluetoothMonitor`: `CBCentralManager` RSSI; 8s silence = absent; paired UUID in Keychain
- `LockTrigger`: Combine hysteresis; absent for N seconds → `triggerPanic()` then `lockScreen()`

## Shoulder Surfing (`Features/ShoulderSurfing/`)
- `AVCaptureSession` + `VNDetectFaceRectanglesRequest` at ~2 fps
- Triggers when 2+ faces detected for `triggerThreshold` consecutive frames

## Core Services
- `SettingsStore`: `@Published` + Combine `.sink` auto-persist to `UserDefaults` + `NSUbiquitousKeyValueStore`
- `CloudSyncStore`: listens for external KV changes, fans out to `SettingsStore`, `AppSafelist`, `LockHistoryStore`

## State Persistence
| Data | Store |
|---|---|
| Settings | `UserDefaults` |
| Safelist | `UserDefaults["panicBlocklist"]` (JSON) |
| Lock history | `UserDefaults["lockHistory"]` (JSON) |
| BT device UUID | Keychain |
| Intruder photos | `~/Pictures/Vigil Screen Captures/<uuid>.jpg` |
| Cloud sync | `NSUbiquitousKeyValueStore` |
