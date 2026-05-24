import XCTest
@testable import VigilScreen

final class PresentationSafelistTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "presentationSafelist")
    }

    @MainActor func testInitialState_containsAppSafelistDefaults() {
        for id in AppSafelist.defaults {
            XCTAssertTrue(
                PresentationSafelist.shared.bundleIDs.contains(id),
                "Expected \(id) in initial presentation safelist"
            )
        }
    }

    @MainActor func testAdd_insertsBundleID() {
        PresentationSafelist.shared.add("com.test.addme")
        XCTAssertTrue(PresentationSafelist.shared.bundleIDs.contains("com.test.addme"))
        PresentationSafelist.shared.remove("com.test.addme")
    }

    @MainActor func testRemove_deletesBundleID() {
        PresentationSafelist.shared.add("com.test.removeme")
        PresentationSafelist.shared.remove("com.test.removeme")
        XCTAssertFalse(PresentationSafelist.shared.bundleIDs.contains("com.test.removeme"))
    }

    @MainActor func testPersistence_savesToUserDefaults() {
        PresentationSafelist.shared.add("com.test.persist")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let saved = UserDefaults.standard.stringArray(forKey: "presentationSafelist") ?? []
        XCTAssertTrue(saved.contains("com.test.persist"))
        PresentationSafelist.shared.remove("com.test.persist")
    }

    @MainActor func testResetFromPanicSafelist_copiesCurrentPanicIDs() {
        let panicIDs = AppSafelist.shared.bundleIDs
        PresentationSafelist.shared.resetFromPanicSafelist()
        XCTAssertEqual(PresentationSafelist.shared.bundleIDs, panicIDs)
    }
}
