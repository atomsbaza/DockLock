import XCTest
import Combine
@testable import VigilScreen

final class PresentationModeManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear persisted history so count-based assertions don't break when the
        // 100-event cap is already reached from prior runs.
        MainActor.assumeIsolated {
            LockHistoryStore.shared.clear()
        }
    }

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
