import XCTest
@testable import VigilScreen

final class AuditSummaryGeneratorTests: XCTestCase {

    @MainActor func testBuildPrompt_containsFormattedEvents() {
        let gen = AuditSummaryGenerator.shared
        let event = LockEvent(trigger: .panic)
        let prompt = gen.buildPrompt(from: [event])
        XCTAssertTrue(prompt.contains("Panic Mode triggered"))
        XCTAssertTrue(prompt.contains("Summarise this privacy session"))
    }

    @MainActor func testBuildPrompt_allTriggerTypes_haveLabels() {
        let gen = AuditSummaryGenerator.shared
        let triggers: [LockTriggerType] = [.proximity, .panic, .shoulderSurfer, .intruderCapture, .presentationMode, .presentationModeRelease]
        for trigger in triggers {
            let event = LockEvent(trigger: trigger)
            let prompt = gen.buildPrompt(from: [event])
            XCTAssertFalse(prompt.contains("unknown"), "Trigger \(trigger) has no label")
        }
    }

    @MainActor func testBuildPrompt_emptyEvents_stillContainsSuffix() {
        let gen = AuditSummaryGenerator.shared
        let prompt = gen.buildPrompt(from: [])
        XCTAssertTrue(prompt.contains("Summarise this privacy session"))
    }

    @MainActor func testBuildPrompt_multipleEvents_allAppear() {
        let gen = AuditSummaryGenerator.shared
        let events = [LockEvent(trigger: .panic), LockEvent(trigger: .proximity)]
        let prompt = gen.buildPrompt(from: events)
        XCTAssertTrue(prompt.contains("Panic Mode triggered"))
        XCTAssertTrue(prompt.contains("Proximity Lock engaged"))
    }
}
