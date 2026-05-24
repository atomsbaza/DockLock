import XCTest
@testable import VigilScreen

// MARK: - State machine tests

final class PanicModeStateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // TouchID auth always fails in tests; disable it so releasePanic() calls unhideAll() directly.
        MainActor.assumeIsolated {
            SettingsStore.shared.panicRequiresTouchID = false
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            SettingsStore.shared.panicRequiresTouchID = false
            if PanicModeManager.shared.isActive {
                PanicModeManager.shared.releasePanic()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
        }
        super.tearDown()
    }

    @MainActor func testIsActive_isFalseInitially() {
        XCTAssertFalse(PanicModeManager.shared.isActive)
    }

    @MainActor func testTriggerPanic_setsIsActiveTrue() {
        PanicModeManager.shared.triggerPanic()
        XCTAssertTrue(PanicModeManager.shared.isActive)
    }

    @MainActor func testReleasePanic_setsIsActiveFalse() {
        PanicModeManager.shared.triggerPanic()
        PanicModeManager.shared.releasePanic()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertFalse(PanicModeManager.shared.isActive)
    }

    @MainActor func testReleasePanic_whenNotActive_remainsFalse() {
        XCTAssertFalse(PanicModeManager.shared.isActive)
        PanicModeManager.shared.releasePanic()
        XCTAssertFalse(PanicModeManager.shared.isActive)
    }

    @MainActor func testTriggerPanic_idempotent_doesNotDoubleRecord() {
        let countBefore = LockHistoryStore.shared.events.count
        PanicModeManager.shared.triggerPanic()
        PanicModeManager.shared.triggerPanic() // already active — no second record
        XCTAssertEqual(LockHistoryStore.shared.events.count, countBefore + 1)
    }

    // MARK: - App activation handler

    @MainActor func testIsSafelisted_returnsFalseByDefault() {
        // XCTest runner is not in the panic safelist by default
        XCTAssertFalse(PanicModeManager.shared.isSafelisted(NSRunningApplication.current))
    }

    @MainActor func testIsSafelisted_returnsTrueAfterAdding() {
        guard let bundleID = NSRunningApplication.current.bundleIdentifier else {
            XCTFail("test process has no bundle identifier"); return
        }
        AppSafelist.shared.add(bundleID)
        defer { AppSafelist.shared.remove(bundleID) }
        XCTAssertTrue(PanicModeManager.shared.isSafelisted(NSRunningApplication.current))
    }

    @MainActor func testHandleAppActivation_safelistedApp_doesNotHide() {
        // Safelist the test process so handleAppActivation skips .hide() on it.
        // Verifies the handler respects the safelisted guard during active panic.
        guard let bundleID = NSRunningApplication.current.bundleIdentifier else {
            XCTFail("test process has no bundle identifier"); return
        }
        AppSafelist.shared.add(bundleID)
        defer { AppSafelist.shared.remove(bundleID) }

        PanicModeManager.shared.triggerPanic()
        // Calling handleAppActivation with a safelisted app must not crash and must
        // leave panic active (the overlay update path is exercised without .hide()).
        PanicModeManager.shared.handleAppActivation(NSRunningApplication.current)
        XCTAssertTrue(PanicModeManager.shared.isActive)
    }
}
