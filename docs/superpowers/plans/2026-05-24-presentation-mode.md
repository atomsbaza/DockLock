# Presentation Mode + Panic Observer Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Presentation Mode (auto-hide apps when screen sharing is detected) and refactor PanicModeManager to use a shared WorkspaceObserver, eliminating a point-in-time runningApplications query.

**Architecture:** A new `WorkspaceObserver` singleton owns all `NSWorkspace` subscriptions and fans out via Combine subjects to two consumers: `ScreenShareDetector` (new) which polls `CGWindowListCopyWindowInfo` every 2s when watched apps are running, and `PanicModeManager` (refactored) which reads from the live cache instead of querying at trigger time. `PresentationModeManager` subscribes to `ScreenShareDetector` events and hides/restores apps using a separate `PresentationSafelist`.

**Tech Stack:** Swift 6, AppKit, Combine, NSWorkspace, CGWindowListCopyWindowInfo, UserDefaults, NSUbiquitousKeyValueStore

> **Note on Xcode targets:** Every new `.swift` file created must be added to the correct Xcode target. After creating each file, open `VigilScreen.xcodeproj` and add it to the target (VigilScreen target for source files, VigilScreenTests target for test files). The build step in each task will fail with "no such module" or missing symbol errors if you forget.

---

## File Map

**New files:**
- `VigilScreen/Core/WorkspaceObserver.swift` — live NSWorkspace app-lifecycle cache + subjects
- `VigilScreen/Features/PresentationMode/PresentationSafelist.swift` — UserDefaults-backed safelist for presentation
- `VigilScreen/Features/PresentationMode/ScreenShareDetector.swift` — polls CGWindowList, fires sharingStarted/sharingStopped
- `VigilScreen/Features/PresentationMode/PresentationModeManager.swift` — hides/restores apps on share events
- `VigilScreen/Features/PresentationMode/PresentationModeView.swift` — settings UI tab
- `VigilScreenTests/WorkspaceObserverTests.swift`
- `VigilScreenTests/PresentationSafelistTests.swift`
- `VigilScreenTests/ScreenShareDetectorTests.swift`
- `VigilScreenTests/PresentationModeManagerTests.swift`

**Modified files:**
- `VigilScreen/Core/LockHistoryStore.swift` — add `.presentationMode`, `.presentationModeRelease` to `LockTriggerType`
- `VigilScreen/Core/SettingsStore.swift` — add `presentationModeEnabled`
- `VigilScreen/Core/CloudSyncStore.swift` — route `presentationWatchlist`, `presentationSafelist`, `presentationModeEnabled`
- `VigilScreen/Features/PanicMode/PanicModeManager.swift` — use `WorkspaceObserver.shared.runningApps`; hide non-safelisted apps on activate
- `VigilScreen/Features/History/LockHistoryView.swift` — green badge for `.presentationMode` events
- `VigilScreen/MenuBar/MenuBarManager.swift` — dot badge when `PresentationModeManager.isActive`
- `VigilScreen/Settings/SettingsView.swift` — add Presentation Mode navigation link
- `VigilScreen/App/AppDelegate.swift` — eager init of new singletons

---

### Task 1: WorkspaceObserver

**Files:**
- Create: `VigilScreen/Core/WorkspaceObserver.swift`
- Create: `VigilScreenTests/WorkspaceObserverTests.swift`

- [ ] **Step 1: Create WorkspaceObserver.swift**

```swift
import AppKit
import Combine

@MainActor
final class WorkspaceObserver: ObservableObject {
    static let shared = WorkspaceObserver()

    @Published private(set) var runningApps: [NSRunningApplication]

    let appLaunched   = PassthroughSubject<NSRunningApplication, Never>()
    let appTerminated = PassthroughSubject<NSRunningApplication, Never>()
    let appActivated  = PassthroughSubject<NSRunningApplication, Never>()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        runningApps = NSWorkspace.shared.runningApplications

        let nc = NSWorkspace.shared.notificationCenter

        nc.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.runningApps = NSWorkspace.shared.runningApplications
                self?.appLaunched.send(app)
            }
            .store(in: &cancellables)

        nc.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.runningApps = NSWorkspace.shared.runningApplications
                self?.appTerminated.send(app)
            }
            .store(in: &cancellables)

        nc.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.appActivated.send(app)
            }
            .store(in: &cancellables)
    }
}
```

- [ ] **Step 2: Add WorkspaceObserver.swift to the VigilScreen target in Xcode**

- [ ] **Step 3: Create WorkspaceObserverTests.swift**

```swift
import XCTest
import Combine
@testable import VigilScreen

final class WorkspaceObserverTests: XCTestCase {

    @MainActor func testRunningApps_nonEmpty() {
        XCTAssertFalse(WorkspaceObserver.shared.runningApps.isEmpty)
    }

    @MainActor func testAppLaunched_firesOnNotification() {
        let exp = expectation(description: "appLaunched")
        var cancellable: AnyCancellable?
        cancellable = WorkspaceObserver.shared.appLaunched
            .first()
            .sink { _ in exp.fulfill(); cancellable?.cancel() }

        let fakeApp = NSWorkspace.shared.runningApplications.first!
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didLaunchApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: fakeApp]
        )
        wait(for: [exp], timeout: 1.0)
    }

    @MainActor func testAppTerminated_firesOnNotification() {
        let exp = expectation(description: "appTerminated")
        var cancellable: AnyCancellable?
        cancellable = WorkspaceObserver.shared.appTerminated
            .first()
            .sink { _ in exp.fulfill(); cancellable?.cancel() }

        let fakeApp = NSWorkspace.shared.runningApplications.first!
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: fakeApp]
        )
        wait(for: [exp], timeout: 1.0)
    }

    @MainActor func testAppActivated_firesOnNotification() {
        let exp = expectation(description: "appActivated")
        var cancellable: AnyCancellable?
        cancellable = WorkspaceObserver.shared.appActivated
            .first()
            .sink { _ in exp.fulfill(); cancellable?.cancel() }

        let fakeApp = NSWorkspace.shared.runningApplications.first!
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: fakeApp]
        )
        wait(for: [exp], timeout: 1.0)
    }
}
```

- [ ] **Step 4: Add WorkspaceObserverTests.swift to the VigilScreenTests target in Xcode**

- [ ] **Step 5: Run the new tests**

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/WorkspaceObserverTests 2>&1 | tail -20
```

Expected: 4 tests pass, 0 fail.

- [ ] **Step 6: Commit**

```bash
git add VigilScreen/Core/WorkspaceObserver.swift VigilScreenTests/WorkspaceObserverTests.swift
git commit -m "feat: add WorkspaceObserver for shared NSWorkspace subscription cache"
```

---

### Task 2: Add .presentationMode to LockTriggerType

**Files:**
- Modify: `VigilScreen/Core/LockHistoryStore.swift`

- [ ] **Step 1: Add new cases to LockTriggerType**

In `LockHistoryStore.swift`, update `LockTriggerType` from:
```swift
enum LockTriggerType: String, Codable {
    case proximity
    case panic
    case intruderCapture
    case shoulderSurfer
}
```
to:
```swift
enum LockTriggerType: String, Codable {
    case proximity
    case panic
    case intruderCapture
    case shoulderSurfer
    case presentationMode
    case presentationModeRelease
}
```

- [ ] **Step 2: Build — check for exhaustive switch errors**

```bash
xcodebuild -scheme VigilScreen -configuration Debug build 2>&1 | grep "error:" | head -20
```

Expected: 0 errors. If any `switch` on `LockTriggerType` is now non-exhaustive, add the missing cases before proceeding.

- [ ] **Step 3: Commit**

```bash
git add VigilScreen/Core/LockHistoryStore.swift
git commit -m "feat: add presentationMode trigger types to LockHistoryStore"
```

---

### Task 3: PresentationSafelist

**Files:**
- Create: `VigilScreen/Features/PresentationMode/PresentationSafelist.swift`
- Create: `VigilScreenTests/PresentationSafelistTests.swift`

- [ ] **Step 1: Write the failing test**

Create `VigilScreenTests/PresentationSafelistTests.swift`:

```swift
import XCTest
@testable import VigilScreen

final class PresentationSafelistTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "presentationSafelist")
    }

    @MainActor func testInitialState_containsAppSafelistDefaults() {
        for id in AppSafelist.defaults {
            XCTAssertTrue(
                PresentationSafelist.shared.bundleIDs.contains(id),
                "Expected \(id) in initial presentation safelist"
            )
        }
    }

    @MainActor func testAdd_insertsBundleID() {
        PresentationSafelist.shared.add("com.test.addme")
        XCTAssertTrue(PresentationSafelist.shared.bundleIDs.contains("com.test.addme"))
        PresentationSafelist.shared.remove("com.test.addme")
    }

    @MainActor func testRemove_deletesBundleID() {
        PresentationSafelist.shared.add("com.test.removeme")
        PresentationSafelist.shared.remove("com.test.removeme")
        XCTAssertFalse(PresentationSafelist.shared.bundleIDs.contains("com.test.removeme"))
    }

    @MainActor func testPersistence_savesToUserDefaults() {
        PresentationSafelist.shared.add("com.test.persist")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let saved = UserDefaults.standard.stringArray(forKey: "presentationSafelist") ?? []
        XCTAssertTrue(saved.contains("com.test.persist"))
        PresentationSafelist.shared.remove("com.test.persist")
    }

    @MainActor func testResetFromPanicSafelist_copiesCurrentPanicIDs() {
        let panicIDs = AppSafelist.shared.bundleIDs
        PresentationSafelist.shared.resetFromPanicSafelist()
        XCTAssertEqual(PresentationSafelist.shared.bundleIDs, panicIDs)
    }
}
```

- [ ] **Step 2: Run — expect compile failure (PresentationSafelist not yet defined)**

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/PresentationSafelistTests 2>&1 | tail -10
```

- [ ] **Step 3: Create PresentationSafelist.swift**

```swift
import Foundation
import Combine
import AppKit

@MainActor
final class PresentationSafelist: ObservableObject {
    static let shared = PresentationSafelist()

    @Published var bundleIDs: Set<String>

    private var cancellable: AnyCancellable?

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: "presentationSafelist") {
            bundleIDs = Set(saved)
        } else {
            let panic = UserDefaults.standard.stringArray(forKey: "panicBlocklist") ?? AppSafelist.defaults
            bundleIDs = Set(panic)
        }

        cancellable = $bundleIDs
            .dropFirst()
            .sink { ids in
                UserDefaults.standard.set(Array(ids), forKey: "presentationSafelist")
                NSUbiquitousKeyValueStore.default.set(Array(ids), forKey: "presentationSafelist")
            }
    }

    func syncFromCloud(_ store: NSUbiquitousKeyValueStore) {
        guard let ids = store.array(forKey: "presentationSafelist") as? [String] else { return }
        bundleIDs = Set(ids)
    }

    func applyCloudUpdate(_ store: NSUbiquitousKeyValueStore) {
        syncFromCloud(store)
    }

    func resetFromPanicSafelist() {
        bundleIDs = AppSafelist.shared.bundleIDs
    }

    func add(_ bundleID: String) {
        bundleIDs.insert(bundleID)
    }

    func remove(_ bundleID: String) {
        bundleIDs.remove(bundleID)
    }
}
```

- [ ] **Step 4: Add PresentationSafelist.swift to VigilScreen target, PresentationSafelistTests.swift to VigilScreenTests target**

- [ ] **Step 5: Run tests — expect pass**

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/PresentationSafelistTests 2>&1 | tail -10
```

Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add VigilScreen/Features/PresentationMode/PresentationSafelist.swift VigilScreenTests/PresentationSafelistTests.swift
git commit -m "feat: add PresentationSafelist model"
```

---

### Task 4: ScreenShareDetector

**Files:**
- Create: `VigilScreen/Features/PresentationMode/ScreenShareDetector.swift`
- Create: `VigilScreenTests/ScreenShareDetectorTests.swift`

- [ ] **Step 1: Write the failing tests**

The heuristic logic is extracted as a `static func isSharing(bundleID:windowTitles:) -> Bool` — a pure function with no side effects. Test it directly without needing a running macOS session.

Create `VigilScreenTests/ScreenShareDetectorTests.swift`:

```swift
import XCTest
@testable import VigilScreen

final class ScreenShareDetectorTests: XCTestCase {

    // MARK: - Zoom

    func testZoom_sharingWindow_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "us.zoom.xos", windowTitles: ["Zoom Meeting", "Chat"]
        ))
    }

    func testZoom_screenSharingBanner_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "us.zoom.xos", windowTitles: ["You are screen sharing"]
        ))
    }

    func testZoom_noSharingWindow_notDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "us.zoom.xos", windowTitles: ["Zoom", "Chat"]
        ))
    }

    // MARK: - Teams

    func testTeams_sharingTitle_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.microsoft.teams2",
            windowTitles: ["Microsoft Teams - Screen sharing"]
        ))
    }

    func testTeams_noSharing_notDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "com.microsoft.teams2", windowTitles: ["Microsoft Teams"]
        ))
    }

    // MARK: - FaceTime

    func testFaceTime_sharePlay_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.apple.facetime", windowTitles: ["SharePlay"]
        ))
    }

    func testFaceTime_screenShare_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.apple.facetime", windowTitles: ["Screen Share"]
        ))
    }

    func testFaceTime_noMatch_notDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "com.apple.facetime", windowTitles: ["FaceTime"]
        ))
    }

    // MARK: - Meet (Chrome)

    func testChrome_meetPlusPresent_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.google.Chrome",
            windowTitles: ["Google Meet - call", "You are presenting"]
        ))
    }

    func testChrome_meetWithoutPresent_notDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "com.google.Chrome", windowTitles: ["Google Meet - call"]
        ))
    }

    // MARK: - Loom

    func testLoom_hasWindow_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.loom.desktop", windowTitles: ["Loom Recording"]
        ))
    }

    // MARK: - Fallback

    func testUnknownApp_sharingTitle_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.unknown.app",
            windowTitles: ["My App - Screen Sharing Active"]
        ))
    }

    func testUnknownApp_noSharingTitle_notDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "com.unknown.app", windowTitles: ["My App"]
        ))
    }

    // MARK: - Empty window list

    func testEmptyWindowList_neverDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "us.zoom.xos", windowTitles: []
        ))
    }

    // MARK: - Watchlist

    @MainActor func testDefaultWatchlist_containsKnownApps() {
        let ids = ScreenShareDetector.shared.watchedBundleIDs
        XCTAssertTrue(ids.contains("us.zoom.xos"))
        XCTAssertTrue(ids.contains("com.google.Chrome"))
        XCTAssertTrue(ids.contains("com.microsoft.teams2"))
        XCTAssertTrue(ids.contains("com.apple.facetime"))
        XCTAssertTrue(ids.contains("com.loom.desktop"))
    }

    @MainActor func testAddToWatchlist_insertsID() {
        ScreenShareDetector.shared.addToWatchlist("com.test.conference")
        XCTAssertTrue(ScreenShareDetector.shared.watchedBundleIDs.contains("com.test.conference"))
        ScreenShareDetector.shared.removeFromWatchlist("com.test.conference")
    }

    @MainActor func testRemoveFromWatchlist_removesID() {
        ScreenShareDetector.shared.addToWatchlist("com.test.remove")
        ScreenShareDetector.shared.removeFromWatchlist("com.test.remove")
        XCTAssertFalse(ScreenShareDetector.shared.watchedBundleIDs.contains("com.test.remove"))
    }
}
```

- [ ] **Step 2: Run — expect compile failure**

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/ScreenShareDetectorTests 2>&1 | tail -10
```

- [ ] **Step 3: Create ScreenShareDetector.swift**

```swift
import AppKit
import Combine

@MainActor
final class ScreenShareDetector: ObservableObject {
    static let shared = ScreenShareDetector()

    let sharingStarted = PassthroughSubject<NSRunningApplication, Never>()
    let sharingStopped = PassthroughSubject<NSRunningApplication, Never>()

    @Published private(set) var isCurrentlySharing = false
    @Published private(set) var watchedBundleIDs: Set<String>

    private static let defaultWatchlist: [String] = [
        "us.zoom.xos",
        "com.google.Chrome",
        "com.microsoft.teams2",
        "com.apple.facetime",
        "com.loom.desktop"
    ]

    private var watchedRunningApps: Set<String> = []
    private var pollingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: "presentationWatchlist") {
            watchedBundleIDs = Set(saved)
        } else {
            watchedBundleIDs = Set(Self.defaultWatchlist)
        }

        $watchedBundleIDs
            .dropFirst()
            .sink { ids in
                UserDefaults.standard.set(Array(ids), forKey: "presentationWatchlist")
                NSUbiquitousKeyValueStore.default.set(Array(ids), forKey: "presentationWatchlist")
            }
            .store(in: &cancellables)

        WorkspaceObserver.shared.appLaunched
            .filter { [weak self] app in
                guard let self, let id = app.bundleIdentifier else { return false }
                return self.watchedBundleIDs.contains(id)
            }
            .sink { [weak self] app in
                guard let id = app.bundleIdentifier else { return }
                self?.watchedRunningApps.insert(id)
                self?.startPollingIfNeeded()
            }
            .store(in: &cancellables)

        WorkspaceObserver.shared.appTerminated
            .sink { [weak self] app in
                guard let self, let id = app.bundleIdentifier,
                      self.watchedBundleIDs.contains(id) else { return }
                self.watchedRunningApps.remove(id)
                if self.watchedRunningApps.isEmpty {
                    self.stopPolling()
                    if self.isCurrentlySharing {
                        self.isCurrentlySharing = false
                        self.sharingStopped.send(app)
                    }
                }
            }
            .store(in: &cancellables)

        // Seed with already-running watched apps at launch
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier,
                  watchedBundleIDs.contains(id) else { continue }
            watchedRunningApps.insert(id)
        }
        startPollingIfNeeded()
    }

    // MARK: - Watchlist

    func addToWatchlist(_ bundleID: String) {
        watchedBundleIDs.insert(bundleID)
    }

    func removeFromWatchlist(_ bundleID: String) {
        watchedBundleIDs.remove(bundleID)
    }

    func syncWatchlistFromCloud(_ store: NSUbiquitousKeyValueStore) {
        guard let ids = store.array(forKey: "presentationWatchlist") as? [String] else { return }
        watchedBundleIDs = Set(ids)
    }

    // MARK: - Polling

    private func startPollingIfNeeded() {
        guard !watchedRunningApps.isEmpty, pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.poll() }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func poll() {
        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []

        let nowSharing = detectSharing(
            runningApps: WorkspaceObserver.shared.runningApps,
            windowList: windowList
        )
        guard nowSharing != isCurrentlySharing else { return }
        isCurrentlySharing = nowSharing

        let triggerApp = WorkspaceObserver.shared.runningApps.first {
            guard let id = $0.bundleIdentifier else { return false }
            return watchedBundleIDs.contains(id)
        }
        if let app = triggerApp {
            if nowSharing { sharingStarted.send(app) } else { sharingStopped.send(app) }
        }
    }

    // MARK: - Heuristics (static for testability)

    static func isSharing(bundleID: String, windowTitles: [String]) -> Bool {
        guard !windowTitles.isEmpty else { return false }
        let lower = windowTitles.map { $0.lowercased() }
        switch bundleID {
        case "us.zoom.xos":
            return lower.contains { $0.contains("zoom meeting") || $0.contains("you are screen sharing") }
        case "com.microsoft.teams2":
            return lower.contains { $0.contains("sharing") }
        case "com.apple.facetime":
            return lower.contains { $0.contains("shareplay") || $0.contains("screen share") }
        case "com.loom.desktop":
            return true  // any window = recording active
        case "com.google.Chrome":
            return lower.contains { $0.contains("meet") } &&
                   lower.contains { $0.contains("present") }
        default:
            return lower.contains { $0.contains("sharing") || $0.contains("screen share") }
        }
    }

    private func detectSharing(runningApps: [NSRunningApplication],
                                windowList: [[String: Any]]) -> Bool {
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  watchedBundleIDs.contains(bundleID) else { continue }
            let pid = app.processIdentifier
            let titles = windowList.compactMap { info -> String? in
                guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                      pid_t(ownerPID) == pid else { return nil }
                return info[kCGWindowName as String] as? String
            }
            if Self.isSharing(bundleID: bundleID, windowTitles: titles) { return true }
        }
        return false
    }
}
```

- [ ] **Step 4: Add both files to Xcode targets**

- [ ] **Step 5: Run tests — expect pass**

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/ScreenShareDetectorTests 2>&1 | tail -20
```

Expected: 17 tests pass.

- [ ] **Step 6: Commit**

```bash
git add VigilScreen/Features/PresentationMode/ScreenShareDetector.swift VigilScreenTests/ScreenShareDetectorTests.swift
git commit -m "feat: add ScreenShareDetector with configurable watchlist and CGWindowList heuristics"
```

---

### Task 5: PresentationModeManager

**Files:**
- Create: `VigilScreen/Features/PresentationMode/PresentationModeManager.swift`
- Create: `VigilScreenTests/PresentationModeManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `VigilScreenTests/PresentationModeManagerTests.swift`:

```swift
import XCTest
import Combine
@testable import VigilScreen

final class PresentationModeManagerTests: XCTestCase {

    override func tearDown() {
        MainActor.assumeIsolated {
            if PresentationModeManager.shared.isActive {
                PresentationModeManager.shared.forceDisengage()
            }
            SettingsStore.shared.panicRequiresTouchID = false
            if PanicModeManager.shared.isActive {
                PanicModeManager.shared.releasePanic()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
        }
        super.tearDown()
    }

    @MainActor func testIsActive_falseInitially() {
        XCTAssertFalse(PresentationModeManager.shared.isActive)
    }

    @MainActor func testEngage_setsIsActiveTrue() {
        PresentationModeManager.shared.forceEngage()
        XCTAssertTrue(PresentationModeManager.shared.isActive)
    }

    @MainActor func testDisengage_setsIsActiveFalse() {
        PresentationModeManager.shared.forceEngage()
        PresentationModeManager.shared.forceDisengage()
        XCTAssertFalse(PresentationModeManager.shared.isActive)
    }

    @MainActor func testEngage_recordsPresentationModeEvent() {
        let countBefore = LockHistoryStore.shared.events.count
        PresentationModeManager.shared.forceEngage()
        XCTAssertEqual(LockHistoryStore.shared.events.count, countBefore + 1)
        XCTAssertEqual(LockHistoryStore.shared.events.first?.trigger, .presentationMode)
    }

    @MainActor func testDisengage_recordsReleaseEvent() {
        PresentationModeManager.shared.forceEngage()
        let countBefore = LockHistoryStore.shared.events.count
        PresentationModeManager.shared.forceDisengage()
        XCTAssertEqual(LockHistoryStore.shared.events.count, countBefore + 1)
        XCTAssertEqual(LockHistoryStore.shared.events.first?.trigger, .presentationModeRelease)
    }

    @MainActor func testEngage_idempotent() {
        PresentationModeManager.shared.forceEngage()
        let countBefore = LockHistoryStore.shared.events.count
        PresentationModeManager.shared.forceEngage()
        XCTAssertEqual(LockHistoryStore.shared.events.count, countBefore)
    }

    @MainActor func testPanicPriority_blocksEngageWhenPanicActive() {
        SettingsStore.shared.panicRequiresTouchID = false
        PanicModeManager.shared.triggerPanic()
        PresentationModeManager.shared.forceEngage()
        XCTAssertFalse(PresentationModeManager.shared.isActive)
    }
}
```

- [ ] **Step 2: Run — expect compile failure**

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/PresentationModeManagerTests 2>&1 | tail -10
```

- [ ] **Step 3: Create PresentationModeManager.swift**

```swift
import AppKit
import Combine

@MainActor
final class PresentationModeManager: ObservableObject {
    static let shared = PresentationModeManager()

    @Published private(set) var isActive = false

    private let safelist = PresentationSafelist.shared
    private var hiddenApps: [NSRunningApplication] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        ScreenShareDetector.shared.sharingStarted
            .sink { [weak self] _ in
                guard SettingsStore.shared.presentationModeEnabled else { return }
                guard !PanicModeManager.shared.isActive else { return }
                self?.engage()
            }
            .store(in: &cancellables)

        ScreenShareDetector.shared.sharingStopped
            .sink { [weak self] _ in self?.disengage() }
            .store(in: &cancellables)

        // Re-evaluate when panic releases: if a share is still active, re-engage
        PanicModeManager.shared.$isActive
            .filter { !$0 }
            .dropFirst()
            .sink { [weak self] _ in
                guard SettingsStore.shared.presentationModeEnabled else { return }
                if ScreenShareDetector.shared.isCurrentlySharing {
                    self?.engage()
                }
            }
            .store(in: &cancellables)
    }

    private func engage() {
        guard !isActive else { return }
        isActive = true
        hiddenApps = WorkspaceObserver.shared.runningApps.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return !safelist.bundleIDs.contains(id) &&
                   app.activationPolicy == .regular &&
                   !app.isHidden
        }
        hiddenApps.forEach { _ = $0.hide() }
        LockHistoryStore.shared.record(.presentationMode)
    }

    private func disengage() {
        guard isActive else { return }
        isActive = false
        let toRestore = hiddenApps
        hiddenApps = []
        toRestore.forEach { app in
            if !app.unhide() {
                print("[PresentationMode] unhide failed: \(app.bundleIdentifier ?? app.localizedName ?? "unknown")")
            }
        }
        LockHistoryStore.shared.record(.presentationModeRelease)
    }

    // MARK: - Internal test entry points (@testable import makes these visible in tests)

    func forceEngage() {
        guard !PanicModeManager.shared.isActive else { return }
        engage()
    }

    func forceDisengage() {
        disengage()
    }
}
```

- [ ] **Step 4: Add both files to Xcode targets**

- [ ] **Step 5: Run tests — expect pass**

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/PresentationModeManagerTests 2>&1 | tail -20
```

Expected: 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add VigilScreen/Features/PresentationMode/PresentationModeManager.swift VigilScreenTests/PresentationModeManagerTests.swift
git commit -m "feat: add PresentationModeManager with engage/disengage and panic-priority logic"
```

---

### Task 6: PanicModeManager refactor

**Files:**
- Modify: `VigilScreen/Features/PanicMode/PanicModeManager.swift`

Two focused changes:
1. `safelistedWindowRects(for:onlyApp:)` — use the cached `WorkspaceObserver.shared.runningApps` instead of querying live.
2. `startMonitoringSpaceSwitches()` — call `.hide()` on non-safelisted apps that activate during panic (event-driven, no polling delay).

- [ ] **Step 1: Replace NSWorkspace.shared.runningApplications in safelistedWindowRects**

In `PanicModeManager.swift`, in `safelistedWindowRects(for:onlyApp:)`, find:
```swift
for app in NSWorkspace.shared.runningApplications {
```
Replace with:
```swift
for app in WorkspaceObserver.shared.runningApps {
```

- [ ] **Step 2: Add .hide() call on non-safelisted apps that activate during panic**

In `startMonitoringSpaceSwitches()`, find:
```swift
center.publisher(for: NSWorkspace.didActivateApplicationNotification)
    .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
    .sink { [weak self] app in self?.updateBlurOverlay(for: app) }
    .store(in: &panicCancellables)
```

Replace with:
```swift
center.publisher(for: NSWorkspace.didActivateApplicationNotification)
    .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
    .sink { [weak self] app in
        guard let self else { return }
        if !self.isSafelisted(app) { _ = app.hide() }
        self.updateBlurOverlay(for: app)
    }
    .store(in: &panicCancellables)
```

- [ ] **Step 3: Build and run existing PanicMode tests**

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/PanicModeStateTests 2>&1 | tail -20
```

Expected: all 5 existing PanicMode tests pass.

- [ ] **Step 4: Commit**

```bash
git add VigilScreen/Features/PanicMode/PanicModeManager.swift
git commit -m "refactor: PanicModeManager reads WorkspaceObserver cache; hides non-safelisted apps on activate"
```

---

### Task 7: SettingsStore + CloudSyncStore wiring

**Files:**
- Modify: `VigilScreen/Core/SettingsStore.swift`
- Modify: `VigilScreen/Core/CloudSyncStore.swift`

- [ ] **Step 1: Add presentationModeEnabled to SettingsStore**

In `SettingsStore.swift`:

Add after the last `@Published var`:
```swift
@Published var presentationModeEnabled: Bool
```

In `private init()`, add after the last initialization line:
```swift
presentationModeEnabled = d.object(forKey: Keys.presentationModeEnabled) as? Bool ?? true
```

Add after the last `persist(...)` call:
```swift
persist(\.$presentationModeEnabled, key: Keys.presentationModeEnabled)
```

In `Keys`, add:
```swift
static let presentationModeEnabled = "presentationModeEnabled"
```

In `Keys.allCloudKeys`, add `presentationModeEnabled` to the array:
```swift
static let allCloudKeys: [String] = [
    panicShortcutEnabled, proximityLockEnabled,
    proximityLockDelay, proximityRSSIThreshold, showMenuBarStats,
    shoulderSurfingSensitivity, shoulderSurfingReleaseDelay,
    presentationModeEnabled
]
```

In `applyCloudUpdate(_:keys:)`, add:
```swift
if keys.contains(Keys.presentationModeEnabled),
   let v = store.object(forKey: Keys.presentationModeEnabled) as? Bool { presentationModeEnabled = v }
```

- [ ] **Step 2: Update CloudSyncStore**

In `CloudSyncStore.swift`:

Update `settingsKeys` to include `presentationModeEnabled`:
```swift
private static let settingsKeys: Set<String> = [
    "panicShortcutEnabled", "proximityLockEnabled",
    "proximityLockDelay", "proximityRSSIThreshold", "showMenuBarStats",
    "presentationModeEnabled"
]
```

In `synchronize()`, add after `LockHistoryStore.shared.syncFromCloud(kvStore)`:
```swift
ScreenShareDetector.shared.syncWatchlistFromCloud(kvStore)
PresentationSafelist.shared.syncFromCloud(kvStore)
```

In `handleExternalChange(_:)`, add after the `panicBlocklist` block:
```swift
if keys.contains("presentationWatchlist") {
    ScreenShareDetector.shared.syncWatchlistFromCloud(kvStore)
}
if keys.contains("presentationSafelist") {
    PresentationSafelist.shared.applyCloudUpdate(kvStore)
}
```

- [ ] **Step 3: Build — verify no errors**

```bash
xcodebuild -scheme VigilScreen -configuration Debug build 2>&1 | grep "error:" | head -20
```

Expected: 0 errors.

- [ ] **Step 4: Run settings tests**

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test -only-testing:VigilScreenTests/SettingsStoreTests 2>&1 | tail -10
```

Expected: all existing settings tests pass.

- [ ] **Step 5: Commit**

```bash
git add VigilScreen/Core/SettingsStore.swift VigilScreen/Core/CloudSyncStore.swift
git commit -m "feat: add presentationModeEnabled to SettingsStore and wire CloudSyncStore routing"
```

---

### Task 8: Settings UI — PresentationModeView + SettingsView tab

**Files:**
- Create: `VigilScreen/Features/PresentationMode/PresentationModeView.swift`
- Modify: `VigilScreen/Settings/SettingsView.swift`

- [ ] **Step 1: Read PanicModeView.swift to match the Form/Section pattern**

```bash
cat VigilScreen/Features/PanicMode/PanicModeView.swift
```

- [ ] **Step 2: Create PresentationModeView.swift following the same pattern**

```swift
import SwiftUI
import AppKit

struct PresentationModeView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var detector = ScreenShareDetector.shared
    @ObservedObject private var safelist = PresentationSafelist.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable Presentation Mode", isOn: $settings.presentationModeEnabled)
                Text("Automatically hides non-safelisted apps when a watched app starts screen sharing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if settings.presentationModeEnabled {
                Section("Watched Apps") {
                    Text("Presentation Mode activates when any of these apps starts screen sharing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(Array(detector.watchedBundleIDs).sorted(), id: \.self) { bundleID in
                        HStack {
                            appIcon(for: bundleID)
                            Text(bundleID)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button { detector.removeFromWatchlist(bundleID) } label: {
                                Image(systemName: "minus.circle").foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Add App…") { pickApp { detector.addToWatchlist($0) } }
                }

                Section("Presentation Safelist") {
                    Text("Apps that stay visible while you are screen sharing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(Array(safelist.bundleIDs).sorted(), id: \.self) { bundleID in
                        HStack {
                            appIcon(for: bundleID)
                            Text(bundleID)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button { safelist.remove(bundleID) } label: {
                                Image(systemName: "minus.circle").foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Button("Add App…") { pickApp { safelist.add($0) } }
                        Button("Reset to Panic Safelist") { safelist.resetFromPanicSafelist() }
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Presentation Mode")
    }

    @ViewBuilder
    private func appIcon(for bundleID: String) -> some View {
        if let icon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon {
            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.dashed").frame(width: 20, height: 20).foregroundColor(.secondary)
        }
    }

    private func pickApp(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Select App"
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty else { return }
        completion(id)
    }
}
```

- [ ] **Step 3: Add PresentationModeView.swift to the VigilScreen target**

- [ ] **Step 4: Add Presentation Mode tab to SettingsView**

In `SettingsView.swift`, inside the `List { }` block, add after the ShoulderSurfing `NavigationLink`:
```swift
NavigationLink(destination: PresentationModeView()) {
    Label("Presentation Mode", systemImage: "rectangle.on.rectangle")
}
```

- [ ] **Step 5: Build — verify no errors**

```bash
xcodebuild -scheme VigilScreen -configuration Debug build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 6: Commit**

```bash
git add VigilScreen/Features/PresentationMode/PresentationModeView.swift VigilScreen/Settings/SettingsView.swift
git commit -m "feat: add Presentation Mode settings UI tab with watchlist and safelist editors"
```

---

### Task 9: LockHistoryView — green badge for presentationMode events

**Files:**
- Modify: `VigilScreen/Features/History/LockHistoryView.swift`

- [ ] **Step 1: Read the current LockHistoryView**

```bash
cat VigilScreen/Features/History/LockHistoryView.swift
```

- [ ] **Step 2: Add presentationMode and presentationModeRelease cases**

Find the `switch` (or conditional) on `LockTriggerType` that maps to a display color. Add:
```swift
case .presentationMode:        // color
    Color.green
case .presentationModeRelease: // color
    Color.green.opacity(0.6)
```

Find the `switch` that maps to a display label string. Add:
```swift
case .presentationMode:
    "Presentation"
case .presentationModeRelease:
    "Presentation End"
```

Match the exact syntax used for the existing cases (could be a `switch` expression, a computed property, or a helper function — adapt to whatever pattern exists).

- [ ] **Step 3: Build — no exhaustive switch warnings**

```bash
xcodebuild -scheme VigilScreen -configuration Debug build 2>&1 | grep "error:" | head -20
```

Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add VigilScreen/Features/History/LockHistoryView.swift
git commit -m "feat: green badge for presentationMode events in Lock History"
```

---

### Task 10: MenuBar — dot badge when Presentation Mode active

**Files:**
- Modify: `VigilScreen/MenuBar/MenuBarManager.swift`

- [ ] **Step 1: Read MenuBarManager.swift and MenuBarView.swift**

```bash
cat VigilScreen/MenuBar/MenuBarManager.swift
cat VigilScreen/MenuBar/MenuBarView.swift
```

- [ ] **Step 2: Add PresentationModeManager observation**

Find where `MenuBarManager` observes `SettingsStore` or `PanicModeManager`. Add an `AnyCancellable` that subscribes to `PresentationModeManager.shared.$isActive` and calls the same status-item update method that the existing RSSI/countdown badge uses.

When `isActive == true`, append `" ◉"` to the button title (or use the same dot indicator pattern already in the file). Set the button tooltip to include `"Presentation Mode active"` when active.

Match the exact pattern used for the existing live stats badge — do not invent a new pattern.

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme VigilScreen -configuration Debug build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 4: Commit**

```bash
git add VigilScreen/MenuBar/MenuBarManager.swift
git commit -m "feat: show dot badge in menu bar when Presentation Mode is active"
```

---

### Task 11: AppDelegate — eager init of new singletons

**Files:**
- Modify: `VigilScreen/App/AppDelegate.swift`

- [ ] **Step 1: Add singleton initialization**

In `applicationDidFinishLaunching`, after `_ = ShoulderSurfingDetector.shared`, add:
```swift
_ = WorkspaceObserver.shared
_ = ScreenShareDetector.shared
_ = PresentationModeManager.shared
```

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme VigilScreen -configuration Debug build 2>&1 | grep "error:" | head -20
```

Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add VigilScreen/App/AppDelegate.swift
git commit -m "feat: eagerly initialize WorkspaceObserver, ScreenShareDetector, PresentationModeManager at launch"
```

---

### Task 12: Full test suite

- [ ] **Step 1: Run all tests**

```bash
xcodebuild -scheme VigilScreenTests -destination 'platform=macOS' test 2>&1 | tail -40
```

Expected: all 39 original tests + new tests pass (0 failures).

- [ ] **Step 2: Fix any failures**

If a test fails due to singleton state leaking between test classes, add a `tearDown()` to the offending test class that resets the relevant shared state and runs the run loop briefly:
```swift
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
```

If a `switch` on `LockTriggerType` is non-exhaustive (warning or error), add the missing `.presentationMode` and `.presentationModeRelease` cases to that switch.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test: full v0.4.0 test suite passing"
```
