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
        XCTAssertFalse(WorkspaceObserver.shared.runningApps.isEmpty, "runningApps should be updated after notification")
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
        XCTAssertFalse(WorkspaceObserver.shared.runningApps.isEmpty, "runningApps should be updated after notification")
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
