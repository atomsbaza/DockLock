import XCTest
@testable import VigilScreen

final class ShoulderSurfingTriggerTests: XCTestCase {

    // MARK: - Threshold formula

    @MainActor func testThreshold_minimumSensitivity() {
        XCTAssertEqual(ShoulderSurfingTrigger.threshold(sensitivity: 0.0), 2)
    }

    @MainActor func testThreshold_maximumSensitivity() {
        XCTAssertEqual(ShoulderSurfingTrigger.threshold(sensitivity: 1.0), 6)
    }

    @MainActor func testThreshold_midSensitivity() {
        XCTAssertEqual(ShoulderSurfingTrigger.threshold(sensitivity: 0.5), 4)
    }

    // MARK: - Counter behaviour

    @MainActor func testProcess_singleFace_doesNotIncrement() {
        var t = ShoulderSurfingTrigger()
        let fired = t.process(faceCount: 1, threshold: 2)
        XCTAssertFalse(fired)
        XCTAssertEqual(t.consecutiveFrames, 0)
    }

    @MainActor func testProcess_zeroFaces_doesNotIncrement() {
        var t = ShoulderSurfingTrigger()
        let fired = t.process(faceCount: 0, threshold: 2)
        XCTAssertFalse(fired)
        XCTAssertEqual(t.consecutiveFrames, 0)
    }

    @MainActor func testProcess_multiFace_incrementsCounter() {
        var t = ShoulderSurfingTrigger()
        _ = t.process(faceCount: 2, threshold: 3)
        XCTAssertEqual(t.consecutiveFrames, 1)
    }

    @MainActor func testProcess_multiFaceBelowThreshold_doesNotTrigger() {
        var t = ShoulderSurfingTrigger()
        let fired = t.process(faceCount: 2, threshold: 3)
        XCTAssertFalse(fired)
    }

    @MainActor func testProcess_reachesThreshold_triggers() {
        var t = ShoulderSurfingTrigger()
        _ = t.process(faceCount: 2, threshold: 2)
        let fired = t.process(faceCount: 2, threshold: 2)
        XCTAssertTrue(fired)
    }

    @MainActor func testProcess_triggerResetsCounter() {
        var t = ShoulderSurfingTrigger()
        _ = t.process(faceCount: 2, threshold: 2)
        _ = t.process(faceCount: 2, threshold: 2) // triggers
        XCTAssertEqual(t.consecutiveFrames, 0)
    }

    @MainActor func testProcess_facesDropToOne_resetsCounter() {
        var t = ShoulderSurfingTrigger()
        _ = t.process(faceCount: 2, threshold: 3)
        _ = t.process(faceCount: 2, threshold: 3)
        XCTAssertEqual(t.consecutiveFrames, 2)
        _ = t.process(faceCount: 1, threshold: 3)
        XCTAssertEqual(t.consecutiveFrames, 0)
    }

    @MainActor func testProcess_interruptedSequence_doesNotTrigger() {
        var t = ShoulderSurfingTrigger()
        _ = t.process(faceCount: 2, threshold: 3)
        _ = t.process(faceCount: 1, threshold: 3) // interrupt — counter resets
        let fired = t.process(faceCount: 2, threshold: 3)
        XCTAssertFalse(fired)
        XCTAssertEqual(t.consecutiveFrames, 1)
    }

    @MainActor func testProcess_threeOrMoreFaces_alsoTriggers() {
        var t = ShoulderSurfingTrigger()
        _ = t.process(faceCount: 3, threshold: 2)
        let fired = t.process(faceCount: 3, threshold: 2)
        XCTAssertTrue(fired)
    }

    @MainActor func testProcess_afterTrigger_canTriggerAgain() {
        var t = ShoulderSurfingTrigger()
        _ = t.process(faceCount: 2, threshold: 1) // triggers, resets
        let fired = t.process(faceCount: 2, threshold: 1) // reaches threshold again
        XCTAssertTrue(fired)
    }
}
