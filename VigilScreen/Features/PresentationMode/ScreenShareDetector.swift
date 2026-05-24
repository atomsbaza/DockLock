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

        SettingsStore.shared.$presentationModeEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.startPollingIfNeeded() } else { self.stopPolling() }
            }
            .store(in: &cancellables)

        // Seed with already-running watched apps at launch
        for app in WorkspaceObserver.shared.runningApps {
            guard let id = app.bundleIdentifier,
                  watchedBundleIDs.contains(id) else { continue }
            watchedRunningApps.insert(id)
        }
        startPollingIfNeeded()
    }

    // MARK: - Watchlist

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

    func removeFromWatchlist(_ bundleID: String) {
        watchedBundleIDs.remove(bundleID)
        watchedRunningApps.remove(bundleID)
        if watchedRunningApps.isEmpty {
            stopPolling()
            if isCurrentlySharing {
                isCurrentlySharing = false
                PresentationModeManager.shared.forceDisengage()
            }
        }
    }

    func syncWatchlistFromCloud(_ store: NSUbiquitousKeyValueStore) {
        guard let ids = store.array(forKey: "presentationWatchlist") as? [String] else { return }
        watchedBundleIDs = Set(ids)
    }

    // MARK: - Polling

    private func startPollingIfNeeded() {
        guard !watchedRunningApps.isEmpty,
              pollingTask == nil,
              SettingsStore.shared.presentationModeEnabled else { return }
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

    nonisolated static func isSharing(bundleID: String, windowTitles: [String]) -> Bool {
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
            return lower.contains { $0.contains("meet") && $0.contains("present") }
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
