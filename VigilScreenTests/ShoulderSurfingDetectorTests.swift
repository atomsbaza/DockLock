import XCTest
@testable import VigilScreen

final class ShoulderSurfingDetectorTests: XCTestCase {

    // MARK: - Credibility filter (pure logic, no camera required)

    func testIsCredibleFace_highConfidenceLargeArea_true() {
        XCTAssertTrue(ShoulderSurfingDetector.isCredibleFace(confidence: 0.9, boundingBoxArea: 0.05))
    }

    func testIsCredibleFace_lowConfidence_false() {
        XCTAssertFalse(ShoulderSurfingDetector.isCredibleFace(confidence: 0.5, boundingBoxArea: 0.05))
    }

    func testIsCredibleFace_tooSmallArea_false() {
        XCTAssertFalse(ShoulderSurfingDetector.isCredibleFace(confidence: 0.9, boundingBoxArea: 0.01))
    }

    func testIsCredibleFace_exactThresholds_true() {
        XCTAssertTrue(ShoulderSurfingDetector.isCredibleFace(confidence: 0.7, boundingBoxArea: 0.02))
    }

    func testIsCredibleFace_confidenceJustBelow_false() {
        XCTAssertFalse(ShoulderSurfingDetector.isCredibleFace(confidence: 0.699, boundingBoxArea: 0.05))
    }

    func testIsCredibleFace_areaJustBelow_false() {
        XCTAssertFalse(ShoulderSurfingDetector.isCredibleFace(confidence: 0.9, boundingBoxArea: 0.019))
    }

    // MARK: - False positive detection

    @MainActor func testHandlePanicRelease_shortDuration_didAutoTrigger_callsRecordFP() {
        let before = SettingsStore.shared.shoulderSurfingFalsePositiveCount
        SettingsStore.shared.shoulderSurfingFalsePositiveCount = 0
        ShoulderSurfingDetector.shared.handlePanicRelease(didAutoTrigger: true, panicDuration: 3.0)
        XCTAssertEqual(SettingsStore.shared.shoulderSurfingFalsePositiveCount, 1)
        SettingsStore.shared.shoulderSurfingFalsePositiveCount = before
    }

    @MainActor func testHandlePanicRelease_longDuration_noFP() {
        let before = SettingsStore.shared.shoulderSurfingFalsePositiveCount
        SettingsStore.shared.shoulderSurfingFalsePositiveCount = 0
        ShoulderSurfingDetector.shared.handlePanicRelease(didAutoTrigger: true, panicDuration: 10.0)
        XCTAssertEqual(SettingsStore.shared.shoulderSurfingFalsePositiveCount, 0)
        SettingsStore.shared.shoulderSurfingFalsePositiveCount = before
    }

    @MainActor func testHandlePanicRelease_notAutoTriggered_noFP() {
        let before = SettingsStore.shared.shoulderSurfingFalsePositiveCount
        SettingsStore.shared.shoulderSurfingFalsePositiveCount = 0
        ShoulderSurfingDetector.shared.handlePanicRelease(didAutoTrigger: false, panicDuration: 1.0)
        XCTAssertEqual(SettingsStore.shared.shoulderSurfingFalsePositiveCount, 0)
        SettingsStore.shared.shoulderSurfingFalsePositiveCount = before
    }

    @MainActor func testRecordFalsePositive_incrementsCount() {
        SettingsStore.shared.shoulderSurfingFalsePositiveCount = 0
        ShoulderSurfingDetector.shared.recordFalsePositive()
        XCTAssertEqual(SettingsStore.shared.shoulderSurfingFalsePositiveCount, 1)
        ShoulderSurfingDetector.shared.recordFalsePositive()
        XCTAssertEqual(SettingsStore.shared.shoulderSurfingFalsePositiveCount, 2)
        SettingsStore.shared.shoulderSurfingFalsePositiveCount = 0
    }
}
