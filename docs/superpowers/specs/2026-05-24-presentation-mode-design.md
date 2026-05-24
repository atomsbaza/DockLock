# Presentation Mode + Panic Mode Observer Refactor — v0.4.0 Design

**Date:** 2026-05-24
**Status:** Approved
**Branch:** `feature/v0.4.0-presentation-mode`

---

## Overview

Two related improvements shipping together in v0.4.0:

1. **Presentation Mode** — auto-detect screen sharing in watched apps (Zoom, Meet, Teams, etc.) and hide non-safelisted apps for the duration of the share. Auto-releases when sharing stops.
2. **Panic Mode observer refactor** — replace the point-in-time `runningApplications` query and 400ms re-hide timer with an event-driven `WorkspaceObserver`, eliminating the race condition.

Both features share the same `WorkspaceObserver` infrastructure.

---

## Architecture

```
WorkspaceObserver (new, Core/)
  ├── ScreenShareDetector (new)   → PresentationModeManager (new)
  └── PanicModeManager (existing, refactored)
```

A single `WorkspaceObserver` singleton owns all `NSWorkspace` subscriptions and fans out to consumers via Combine. No logic lives in the observer itself — it is pure plumbing.

---

## Component: WorkspaceObserver

**Location:** `VigilScreen/Core/WorkspaceObserver.swift`

`@MainActor final class`, initialized at app launch in `AppDelegate` alongside existing singletons.

```swift
@Published var runningApps: [NSRunningApplication]

appLaunched:    PassthroughSubject<NSRunningApplication, Never>
appTerminated:  PassthroughSubject<NSRunningApplication, Never>
appActivated:   PassthroughSubject<NSRunningApplication, Never>
```

Subscribes to four `NSWorkspace.shared.notificationCenter` notifications on init: `didLaunchApplication`, `didTerminateApplication`, `didActivateApplication`, `didDeactivateApplication`. Updates `runningApps` cache and fires the matching subject. No filtering — consumers filter for their own needs.

### Panic Mode refactor

`PanicModeManager` drops its `NSWorkspace.shared.runningApplications` call at trigger time and reads `WorkspaceObserver.shared.runningApps` instead. During active panic, it subscribes to `appActivated` and calls `.hide()` immediately on any non-safelisted app that surfaces — replacing the 400ms re-hide timer entirely.

---

## Component: ScreenShareDetector

**Location:** `VigilScreen/Features/PresentationMode/ScreenShareDetector.swift`

`@MainActor final class`. Watches `WorkspaceObserver.appLaunched` / `appTerminated` to track watched apps. Polls `CGWindowListCopyWindowInfo` at 2s intervals when any watched app is running. Stops polling when no watched apps are running (zero CPU at idle).

**Watched app list** — persisted as `UserDefaults["presentationWatchlist"]` (JSON `[String]` of bundle IDs).

Default watchlist:
- `us.zoom.xos` (Zoom)
- `com.google.Chrome` (Meet via browser — detected by window title)
- `com.microsoft.teams2` (Teams)
- `com.apple.facetime`
- `com.loom.desktop`

**Share detection heuristics** (via `CGWindowListCopyWindowInfo`):

| App | Signal |
|---|---|
| Zoom | Window titled `"Zoom Meeting"` or containing `"You are screen sharing"` |
| Teams | Window title containing `"sharing"` |
| Meet (Chrome) | Chrome window titled containing `"Meet"` + secondary `"Present"` window |
| FaceTime | Window titled `"SharePlay"` or `"Screen Share"` |
| Loom | Recording-indicator window present |
| Fallback | Any watched app window whose title contains `"sharing"` or `"screen share"` (case-insensitive) |

**Publishes:**
```swift
sharingStarted: PassthroughSubject<NSRunningApplication, Never>
sharingStopped: PassthroughSubject<NSRunningApplication, Never>
```

---

## Component: PresentationModeManager

**Location:** `VigilScreen/Features/PresentationMode/PresentationModeManager.swift`

`@MainActor final class`. Subscribes to `ScreenShareDetector.sharingStarted` / `sharingStopped`.

**On `sharingStarted`:**
1. Snapshot currently visible apps for exact restore
2. Hide all non-safelisted `NSRunningApplication`s using the Presentation safelist (same `.hide()` path as Panic Mode)
3. Set `isActive = true` — menu bar icon shows a dot badge
4. Write a `LockHistory` entry with `.presentationMode` event type

**On `sharingStopped`:**
1. Restore snapshotted apps via `.unhide()`
2. Set `isActive = false`, clear badge
3. Write a `LockHistory` release entry

**Presentation safelist** — stored as `UserDefaults["presentationSafelist"]` (JSON `[String]`). Copied from `panicBlocklist` on first launch. Managed via a `PresentationSafelist` model mirroring the existing `AppSafelist` pattern.

**Panic priority** — if Panic Mode fires while Presentation Mode is active, Panic takes priority. `PresentationModeManager` remains engaged (`isActive` stays `true`, `hiddenApps` preserved) — no state suspension needed because panic hides everything independently. On panic release, `PresentationModeManager` re-evaluates whether a watched app is still sharing and re-engages if so (hidden apps stay hidden until sharing stops).

---

## Settings UI

**Location:** `VigilScreen/Settings/PresentationModeSettingsView.swift`

New tab in Settings alongside Panic Mode, Proximity Lock, Shoulder Surfing.

```
Presentation Mode
├── Toggle: Enable Presentation Mode
├── Section: Watched Apps
│   ├── List (app icon + name + bundle ID)
│   ├── [+] Add — NSOpenPanel filtered to .app bundles
│   └── [−] Remove selected
└── Section: Presentation Safelist
    ├── "Apps visible during screen sharing"
    ├── List (app icon + name)
    ├── [+] Add app
    └── "Reset to Panic Mode safelist" link
```

**Menu bar indicator** — dot badge on menu bar icon when `isActive`. Tooltip: `"Presentation Mode active"`.

**Lock History** — new green badge for `.presentationMode` events. Existing badges: Panic = red, Proximity = orange, Shoulder = purple.

---

## Data Persistence

| Key | Type | Default |
|---|---|---|
| `presentationModeEnabled` | `Bool` | `true` |
| `presentationWatchlist` | JSON `[String]` | Zoom, Meet, Teams, FaceTime, Loom |
| `presentationSafelist` | JSON `[String]` | Copied from `panicBlocklist` on first launch |

All three keys sync via `NSUbiquitousKeyValueStore` through the existing `CloudSyncStore` fan-out path.

---

## Error Handling

- **CGWindowList returns empty** — treat as not sharing, stay in current state. No false triggers.
- **Watched app terminates mid-share** — `WorkspaceObserver.appTerminated` fires; `ScreenShareDetector` fires `sharingStopped`; `PresentationModeManager` restores apps normally.
- **Unhide fails** — log to `LockHistoryStore` with an `.error` tag; do not swallow silently.
- **Presentation Mode active when panic fires** — Panic Mode takes priority; `PresentationModeManager` stays engaged internally. On panic release, it re-evaluates sharing state and re-engages if still sharing.

---

## Testing

New test files in `VigilScreenTests/`:

- `WorkspaceObserverTests` — mock `NSWorkspace` notifications; verify cache updates and subject emissions.
- `ScreenShareDetectorTests` — inject fake `CGWindowListCopyWindowInfo` results; verify `sharingStarted` / `sharingStopped` fire correctly per heuristic.
- `PresentationModeManagerTests` — verify hide/restore sequence, history entry creation, panic-priority behaviour.
- `PanicModeManagerTests` (extended) — verify 400ms timer removed; verify activate-event re-hide fires immediately.

---

## Scope (v0.4.0)

**In:**
- `WorkspaceObserver` + Panic Mode refactor
- `ScreenShareDetector` with configurable watchlist
- `PresentationModeManager` with Presentation safelist
- Settings tab + menu bar badge + Lock History badge
- iCloud sync for new keys

**Out (future):**
- Notification redaction during sharing
- Per-app heuristic configuration UI
- Touch ID gate on Presentation Mode release
