# Scrutinize: v0.4.0 Presentation Mode
**Date:** 2026-05-24
**Branch:** `feature/v0.4.0-presentation-mode`
**Verdict:** Fix-then-ship

---

## Intent

Auto-hide non-safelisted apps when a watched app is detected screen-sharing (via CGWindowList polling), and refactor `PanicModeManager` to read a shared `NSWorkspace` cache instead of querying live.

---

## Findings

### 🔴 BLOCKER 1 — The sharing app gets hidden by Presentation Mode

**File:** `VigilScreen/Features/PresentationMode/PresentationModeManager.swift:43-48`

**Finding:** `engage()` hides every regular non-safelisted app. The watched sharing app (Zoom, Teams, FaceTime, Loom) is the *trigger*, not a member of the default `PresentationSafelist`. The default safelist is seeded from `panicBlocklist` — which is the set of apps visible *during panic* (password managers, etc.) — not the screen-sharing app.

**Evidence:** trace `engage()` after `sharingStarted.send(zoomApp)`. `safelist.bundleIDs` does not contain `us.zoom.xos`. `app.activationPolicy == .regular` is true for Zoom. → Zoom is added to `hiddenApps` and `.hide()` is called on it. The user's screen share now shows a hidden Zoom window.

**Suggested fix:** In the `engage()` filter, also exclude any app whose `bundleIdentifier ∈ ScreenShareDetector.shared.watchedBundleIDs`. Simplest one-liner addition:
```swift
&& !ScreenShareDetector.shared.watchedBundleIDs.contains(id)
```

---

### 🔴 BLOCKER 2 — `removeFromWatchlist` while sharing leaves PresentationMode engaged forever

**File:** `VigilScreen/Features/PresentationMode/ScreenShareDetector.swift` — `removeFromWatchlist`

**Finding:**
```swift
func removeFromWatchlist(_ bundleID: String) {
    watchedBundleIDs.remove(bundleID)
    watchedRunningApps.remove(bundleID)
    if watchedRunningApps.isEmpty { stopPolling() }
}
```
Does not reset `isCurrentlySharing` or emit `sharingStopped`. If the user removes the actively-sharing app from the watchlist, `stopPolling()` halts the only path that could fire `sharingStopped`. `PresentationModeManager.isActive` stays `true` with no path to disengage. Quitting Vigil Screen is the only recovery.

**Suggested fix:** After removing, if `isCurrentlySharing` and no remaining watched app is still sharing, reset and emit:
```swift
if isCurrentlySharing {
    isCurrentlySharing = false
    // fire with any remaining running watched app, or a placeholder
    if let app = WorkspaceObserver.shared.runningApps.first(where: {
        guard let id = $0.bundleIdentifier else { return false }
        return watchedBundleIDs.contains(id)
    }) {
        sharingStopped.send(app)
    } else {
        // no watched app running at all — PresentationModeManager must still disengage
        // expose a direct disengage path or store last trigger app
    }
}
```
Alternatively, expose `PresentationModeManager.shared.forceDisengage()` and call it directly here when `watchedRunningApps` becomes empty while sharing.

---

### 🟠 MAJOR 1 — `addToWatchlist` for an already-running app never starts polling

**File:** `VigilScreen/Features/PresentationMode/ScreenShareDetector.swift` — `addToWatchlist`

**Finding:** `addToWatchlist` only inserts into `watchedBundleIDs`. The seeding loop that populates `watchedRunningApps` runs once in `init`. After init, `watchedRunningApps` is only updated via `appLaunched`. So: launch Vigil Screen, then add Zoom (already running) to the watchlist → `pollingTask` remains nil → sharing never detected for that app in this session.

**Suggested fix:**
```swift
func addToWatchlist(_ bundleID: String) {
    watchedBundleIDs.insert(bundleID)
    let isRunning = WorkspaceObserver.shared.runningApps.contains {
        $0.bundleIdentifier == bundleID
    }
    if isRunning {
        watchedRunningApps.insert(bundleID)
        startPollingIfNeeded()
    }
}
```

---

### 🟠 MAJOR 2 — Menu bar "dot badge" is a tooltip only — no visible indicator

**File:** `VigilScreen/MenuBar/MenuBarManager.swift` — `updateIcon`

**Finding:** Design spec (`docs/superpowers/specs/2026-05-24-presentation-mode-design.md:131`) calls for "a dot badge on menu bar icon when isActive." Implementation only sets `button.toolTip`. There is no visible change to the icon when Presentation Mode is active — a user mid-share has no way to know the feature is engaged without hovering.

**Suggested fix:** Append a glyph to the button title when active and panic is not also active:
```swift
if presentationActive && !panicActive {
    statusItem?.button?.title = " ●"
} else {
    // existing BT stats logic
}
```
Or composite a small filled-circle badge onto the SF Symbol image via `NSImage` drawing.

---

### 🟡 MINOR 1 — Polling runs even when `presentationModeEnabled = false`

**File:** `VigilScreen/Features/PresentationMode/ScreenShareDetector.swift`

`ScreenShareDetector` polls every 2s as long as a watched app is running, regardless of `SettingsStore.shared.presentationModeEnabled`. The guard lives only in `PresentationModeManager.sink`. Wasted CPU when the feature is disabled but a watched app (e.g. Zoom) is open.

**Suggested fix:** Gate `startPollingIfNeeded` on `SettingsStore.shared.presentationModeEnabled`, and subscribe to `$presentationModeEnabled` to start/stop polling on toggle.

---

### 🟡 MINOR 2 — Chrome heuristic false-positive with unrelated tabs

**File:** `VigilScreen/Features/PresentationMode/ScreenShareDetector.swift` — `isSharing` for `com.google.Chrome`

Current logic: `any window contains "meet"` AND `any window contains "present"`. A user with a "Google Meet — call" tab open alongside a "Presentation - Google Slides" tab triggers Presentation Mode without actually sharing.

**Suggested fix:** Require both substrings in the *same* window title:
```swift
case "com.google.Chrome":
    return lower.contains { $0.contains("meet") && $0.contains("present") }
```

---

### 🟡 MINOR 3 — Panic-priority spec drift

Design spec says "PresentationModeManager suspends state" while panic is active. Implementation leaves `isActive = true` and `hiddenApps` populated during panic. The re-engage path on panic release no-ops because `engage()`'s `guard !isActive` short-circuits. Nothing user-visible breaks in practice, but the code intent diverges from the spec.

**Suggested fix:** Either update the spec to match the implementation (panic does not suspend; presentation's hidden-apps survive panic), or explicitly `disengage` on panic engage and re-engage on release.

---

### 🟡 MINOR 4 — Plan called for "verify 400ms timer removed" test; not delivered

**File:** `VigilScreenTests/PanicModeManagerTests.swift`

Task 6 only ran existing PanicModeManagerTests. No test exercises the new `.hide()` in `didActivateApplicationNotification`. The plan's testing section called for verifying this behavior.

**Suggested fix:** Add a test that posts a fake `didActivateApplicationNotification` for a non-safelisted app while panic is active and asserts the app receives `.hide()`. May require DI or factoring the handler body into a directly-callable method.

---

### Nit — `ScreenShareDetector.init` reads `NSWorkspace.shared.runningApplications` directly

**File:** `VigilScreen/Features/PresentationMode/ScreenShareDetector.swift:585-589`

The seeding loop at launch calls `NSWorkspace.shared.runningApplications` instead of `WorkspaceObserver.shared.runningApps`. Same data, but inconsistent with the goal of a single source of truth.

---

## Verdict

**Fix-then-ship.** Blockers 1 and 2 will hit the very first user who screen-shares (Blocker 1 immediately hides the sharing app; Blocker 2 makes the feature unrecoverable without restart). Both are small, localized fixes. Major items 1 and 2 are also small. Recommend a v0.4.1 patch addressing findings 1–4 before merging to main.
