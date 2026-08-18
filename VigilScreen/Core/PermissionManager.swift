import AppKit
import Combine

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var hasAccessibilityPermission: Bool = false

    private var pollTimer: Timer?
    private var pollCount = 0
    /// Stop polling after 60 attempts (60 s) to avoid running forever if the user ignores the prompt.
    private let maxPollCount = 60

    private init() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func requestAccessibilityIfNeeded() {
        // Open System Settings → Privacy & Security → Accessibility directly.
        // On macOS 13+, AXIsProcessTrustedWithOptions only shows a redirect dialog;
        // opening the pane directly is more reliable.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
        startPolling()
    }

    /// Polls every second until permission is granted or maxPollCount is reached.
    private func startPolling() {
        guard pollTimer == nil else { return }
        pollCount = 0
        // scheduledTimer is created on the main actor, so it fires on the main run loop.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollAccessibilityPermission()
            }
        }
    }

    private func pollAccessibilityPermission() {
        pollCount += 1
        let granted = AXIsProcessTrusted()
        if hasAccessibilityPermission != granted {
            hasAccessibilityPermission = granted
        }
        if granted || pollCount >= maxPollCount {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}
