## Swift 6 Concurrency
- `@MainActor` on all classes touching UI, `NSApplication`, `NSWindow`, status items
- `Sendable` on types crossing actor boundaries
- Combine publishers for cross-actor observation — prefer over `Task` + `await`
- `CBCentralManagerDelegate`, `AVFoundation`, `Vision`, `NSEvent` global monitors → dispatch to `@MainActor` before touching shared state
- `nonisolated(unsafe)` only when single-queue-access is guaranteed (e.g., `visionQueue`)

## Coding Conventions
- All managers are singletons (`static let shared`) initialized lazily; no init params
- New features: `Features/<FeatureName>/` with Manager/Detector + View pair
- Settings additions: `@Published var` + `persist(\.prop, key:)` + `Keys` enum + `allCloudKeys` if cross-Mac
- No third-party dependencies
- No telemetry, analytics, or network calls
- macOS 26 Liquid Glass: gate `.glassEffect` behind `#available(macOS 26, *)`
- Version bumping: `/version-bump <x.y.z>` slash command

## Test Coverage (82 tests, all passing)
- `AppBlocklistTests` — safelist CRUD and persistence
- `SettingsStoreTests` — defaults, clamping, round-trip
- `DiscoveredDeviceTests` — RSSI signal classification
- `LockTriggerTests` — countdown logic, no-op states
- `BluetoothMonitorTests` — scan state, pairing, presence timer
- `PanicModeManagerTests` — state machine (active/inactive, idempotency)
- `WorkspaceObserverTests` — notification cache and subject emission
- `PresentationSafelistTests` — CRUD, persistence, reset from panic safelist
- `ScreenShareDetectorTests` — per-app heuristics, watchlist mutations
- `PresentationModeManagerTests` — engage/disengage, history entries, panic priority

Not unit-testable: BT scanning, `CGSession` lock, Touch ID, `NSApplication.hide()`, camera, AX interactions.
