import XCTest
@testable import VigilScreen

final class ScreenShareDetectorTests: XCTestCase {

    // MARK: - Zoom

    func testZoom_sharingWindow_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "us.zoom.xos", windowTitles: ["Zoom Meeting", "Chat"]
        ))
    }

    func testZoom_screenSharingBanner_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "us.zoom.xos", windowTitles: ["You are screen sharing"]
        ))
    }

    func testZoom_noSharingWindow_notDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "us.zoom.xos", windowTitles: ["Zoom", "Chat"]
        ))
    }

    // MARK: - Teams

    func testTeams_sharingTitle_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.microsoft.teams2",
            windowTitles: ["Microsoft Teams - Screen sharing"]
        ))
    }

    func testTeams_noSharing_notDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "com.microsoft.teams2", windowTitles: ["Microsoft Teams"]
        ))
    }

    // MARK: - FaceTime

    func testFaceTime_sharePlay_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.apple.facetime", windowTitles: ["SharePlay"]
        ))
    }

    func testFaceTime_screenShare_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.apple.facetime", windowTitles: ["Screen Share"]
        ))
    }

    func testFaceTime_noMatch_notDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "com.apple.facetime", windowTitles: ["FaceTime"]
        ))
    }

    // MARK: - Meet (Chrome)

    func testChrome_meetPlusPresent_sameWindow_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.google.Chrome",
            windowTitles: ["Presenting - Google Meet"]
        ))
    }

    func testChrome_meetWithoutPresent_notDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "com.google.Chrome", windowTitles: ["Google Meet - call"]
        ))
    }

    func testChrome_meetAndPresentInSeparateWindows_notDetected() {
        // "meet" in one tab, "present" in another — must not trigger false positive
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "com.google.Chrome",
            windowTitles: ["Google Meet - call", "Presentation - Google Slides"]
        ))
    }

    // MARK: - Loom

    func testLoom_hasWindow_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.loom.desktop", windowTitles: ["Loom Recording"]
        ))
    }

    // MARK: - Fallback

    func testUnknownApp_sharingTitle_detected() {
        XCTAssertTrue(ScreenShareDetector.isSharing(
            bundleID: "com.unknown.app",
            windowTitles: ["My App - Screen Sharing Active"]
        ))
    }

    func testUnknownApp_noSharingTitle_notDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "com.unknown.app", windowTitles: ["My App"]
        ))
    }

    // MARK: - Empty window list

    func testEmptyWindowList_neverDetected() {
        XCTAssertFalse(ScreenShareDetector.isSharing(
            bundleID: "us.zoom.xos", windowTitles: []
        ))
    }

    // MARK: - Watchlist

    @MainActor func testDefaultWatchlist_containsKnownApps() {
        let ids = ScreenShareDetector.shared.watchedBundleIDs
        XCTAssertTrue(ids.contains("us.zoom.xos"))
        XCTAssertTrue(ids.contains("com.google.Chrome"))
        XCTAssertTrue(ids.contains("com.microsoft.teams2"))
        XCTAssertTrue(ids.contains("com.apple.facetime"))
        XCTAssertTrue(ids.contains("com.loom.desktop"))
    }

    @MainActor func testAddToWatchlist_insertsID() {
        ScreenShareDetector.shared.addToWatchlist("com.test.conference")
        XCTAssertTrue(ScreenShareDetector.shared.watchedBundleIDs.contains("com.test.conference"))
        ScreenShareDetector.shared.removeFromWatchlist("com.test.conference")
    }

    @MainActor func testRemoveFromWatchlist_removesID() {
        ScreenShareDetector.shared.addToWatchlist("com.test.remove")
        ScreenShareDetector.shared.removeFromWatchlist("com.test.remove")
        XCTAssertFalse(ScreenShareDetector.shared.watchedBundleIDs.contains("com.test.remove"))
    }
}
