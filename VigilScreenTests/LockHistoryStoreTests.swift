import XCTest
@testable import VigilScreen

final class LockHistoryStoreTests: XCTestCase {

    // MARK: - Merge (regression for uniquingKeysWith trap)

    @MainActor func testMerge_duplicateUUID_localWins() {
        let sharedID = UUID()
        let local = LockEvent(id: sharedID, trigger: .panic)
        let cloud  = LockEvent(id: sharedID, trigger: .proximity)
        let result = LockHistoryStore.merge(local: [local], cloud: [cloud])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].trigger, .panic)
    }

    @MainActor func testMerge_noOverlap_combinesBoth() {
        let local = LockEvent(trigger: .panic)
        let cloud  = LockEvent(trigger: .proximity)
        let result = LockHistoryStore.merge(local: [local], cloud: [cloud])
        XCTAssertEqual(result.count, 2)
    }

    @MainActor func testMerge_emptyCloud_returnsLocal() {
        let local = LockEvent(trigger: .panic)
        let result = LockHistoryStore.merge(local: [local], cloud: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].trigger, .panic)
    }
}
