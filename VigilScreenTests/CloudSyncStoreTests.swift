import XCTest
@testable import VigilScreen

/// Tests that applyCloudUpdate correctly fans out values from NSUbiquitousKeyValueStore
/// to the appropriate store properties.
/// NSUbiquitousKeyValueStore.default buffers writes locally — no iCloud account required.
/// Uses presentationModeEnabled and showMenuBarStats — keys not touched by SettingsStoreTests —
/// to avoid parallel-test-class interference on shared singletons.
final class CloudSyncStoreTests: XCTestCase {

    private let kv = NSUbiquitousKeyValueStore.default

    // MARK: - SettingsStore fan-out

    @MainActor func testApplyCloudUpdate_presentationModeEnabled_updatesSettings() {
        let original = SettingsStore.shared.presentationModeEnabled
        defer { SettingsStore.shared.presentationModeEnabled = original }

        kv.set(!original, forKey: "presentationModeEnabled")
        SettingsStore.shared.applyCloudUpdate(kv, keys: ["presentationModeEnabled"])

        XCTAssertEqual(SettingsStore.shared.presentationModeEnabled, !original)
    }

    @MainActor func testApplyCloudUpdate_showMenuBarStats_updatesSettings() {
        let original = SettingsStore.shared.showMenuBarStats
        defer { SettingsStore.shared.showMenuBarStats = original }

        kv.set(!original, forKey: "showMenuBarStats")
        SettingsStore.shared.applyCloudUpdate(kv, keys: ["showMenuBarStats"])

        XCTAssertEqual(SettingsStore.shared.showMenuBarStats, !original)
    }

    @MainActor func testApplyCloudUpdate_unrelatedKey_doesNotChangeSettings() {
        let original = SettingsStore.shared.presentationModeEnabled
        defer { SettingsStore.shared.presentationModeEnabled = original }

        kv.set(!original, forKey: "presentationModeEnabled")
        // Pass a different key — should not touch presentationModeEnabled
        SettingsStore.shared.applyCloudUpdate(kv, keys: ["showMenuBarStats"])

        XCTAssertEqual(SettingsStore.shared.presentationModeEnabled, original)
    }

    @MainActor func testApplyCloudUpdate_multipleKeys_updatesAll() {
        let origPresentation = SettingsStore.shared.presentationModeEnabled
        let origStats = SettingsStore.shared.showMenuBarStats
        defer {
            SettingsStore.shared.presentationModeEnabled = origPresentation
            SettingsStore.shared.showMenuBarStats = origStats
        }

        kv.set(!origPresentation, forKey: "presentationModeEnabled")
        kv.set(!origStats, forKey: "showMenuBarStats")
        SettingsStore.shared.applyCloudUpdate(kv, keys: ["presentationModeEnabled", "showMenuBarStats"])

        XCTAssertEqual(SettingsStore.shared.presentationModeEnabled, !origPresentation)
        XCTAssertEqual(SettingsStore.shared.showMenuBarStats, !origStats)
    }

    // MARK: - Security keys must not be synced from cloud

    @MainActor func testApplyCloudUpdate_panicRequiresTouchID_isNotSyncedFromCloud() {
        let original = SettingsStore.shared.panicRequiresTouchID
        defer { SettingsStore.shared.panicRequiresTouchID = original }

        kv.set(!original, forKey: "panicRequiresTouchID")
        SettingsStore.shared.applyCloudUpdate(kv, keys: ["panicRequiresTouchID"])

        XCTAssertEqual(SettingsStore.shared.panicRequiresTouchID, original,
                       "panicRequiresTouchID is a per-machine security control and must not be overwritten by cloud sync")
    }

    @MainActor func testApplyCloudUpdate_intruderCaptureEnabled_isNotSyncedFromCloud() {
        let original = SettingsStore.shared.intruderCaptureEnabled
        defer { SettingsStore.shared.intruderCaptureEnabled = original }

        kv.set(!original, forKey: "intruderCaptureEnabled")
        SettingsStore.shared.applyCloudUpdate(kv, keys: ["intruderCaptureEnabled"])

        XCTAssertEqual(SettingsStore.shared.intruderCaptureEnabled, original,
                       "intruderCaptureEnabled is a per-machine security control and must not be overwritten by cloud sync")
    }

    @MainActor func testApplyCloudUpdate_shoulderSurfingEnabled_isNotSyncedFromCloud() {
        let original = SettingsStore.shared.shoulderSurfingEnabled
        defer { SettingsStore.shared.shoulderSurfingEnabled = original }

        kv.set(!original, forKey: "shoulderSurfingEnabled")
        SettingsStore.shared.applyCloudUpdate(kv, keys: ["shoulderSurfingEnabled"])

        XCTAssertEqual(SettingsStore.shared.shoulderSurfingEnabled, original,
                       "shoulderSurfingEnabled is a per-machine security control and must not be overwritten by cloud sync")
    }
}
