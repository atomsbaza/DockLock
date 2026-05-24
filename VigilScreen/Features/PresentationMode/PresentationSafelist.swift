import Foundation
import Combine
import AppKit

@MainActor
final class PresentationSafelist: ObservableObject {
    static let shared = PresentationSafelist()

    @Published var bundleIDs: Set<String>

    private var cancellable: AnyCancellable?

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: "presentationSafelist") {
            bundleIDs = Set(saved)
        } else {
            let panic = UserDefaults.standard.stringArray(forKey: "panicBlocklist") ?? AppSafelist.defaults
            bundleIDs = Set(panic)
        }

        cancellable = $bundleIDs
            .dropFirst()
            .sink { ids in
                UserDefaults.standard.set(Array(ids), forKey: "presentationSafelist")
                NSUbiquitousKeyValueStore.default.set(Array(ids), forKey: "presentationSafelist")
            }
    }

    func syncFromCloud(_ store: NSUbiquitousKeyValueStore) {
        guard let ids = store.array(forKey: "presentationSafelist") as? [String] else { return }
        bundleIDs = Set(ids)
    }

    func applyCloudUpdate(_ store: NSUbiquitousKeyValueStore) {
        syncFromCloud(store)
    }

    func resetFromPanicSafelist() {
        bundleIDs = AppSafelist.shared.bundleIDs
    }

    func add(_ bundleID: String) {
        bundleIDs.insert(bundleID)
    }

    func remove(_ bundleID: String) {
        bundleIDs.remove(bundleID)
    }
}
