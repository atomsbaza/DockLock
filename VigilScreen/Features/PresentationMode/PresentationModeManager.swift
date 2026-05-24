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
        let watchedIDs = ScreenShareDetector.shared.watchedBundleIDs
        hiddenApps = WorkspaceObserver.shared.runningApps.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return !safelist.bundleIDs.contains(id) &&
                   !watchedIDs.contains(id) &&
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
