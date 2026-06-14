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
}
