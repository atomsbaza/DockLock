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
            .sink { [weak self] app in
                self?.runningApps = NSWorkspace.shared.runningApplications
                self?.appLaunched.send(app)
            }
            .store(in: &cancellables)

        nc.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in
                self?.runningApps = NSWorkspace.shared.runningApplications
                self?.appTerminated.send(app)
            }
            .store(in: &cancellables)

        nc.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in
                self?.appActivated.send(app)
            }
            .store(in: &cancellables)
    }
}
