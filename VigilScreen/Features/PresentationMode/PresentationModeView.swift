import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PresentationModeView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var detector = ScreenShareDetector.shared
    @ObservedObject private var safelist = PresentationSafelist.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable Presentation Mode", isOn: $settings.presentationModeEnabled)
                Text("Automatically hides non-safelisted apps when a watched app starts screen sharing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if settings.presentationModeEnabled {
                Section("Watched Apps") {
                    Text("Presentation Mode activates when any of these apps starts screen sharing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(Array(detector.watchedBundleIDs).sorted(), id: \.self) { bundleID in
                        HStack {
                            appIcon(for: bundleID)
                            Text(bundleID)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button { detector.removeFromWatchlist(bundleID) } label: {
                                Image(systemName: "minus.circle").foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Add App…") { pickApp { detector.addToWatchlist($0) } }
                }

                Section("Presentation Safelist") {
                    Text("Apps that stay visible while you are screen sharing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(Array(safelist.bundleIDs).sorted(), id: \.self) { bundleID in
                        HStack {
                            appIcon(for: bundleID)
                            Text(bundleID)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button { safelist.remove(bundleID) } label: {
                                Image(systemName: "minus.circle").foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Button("Add App…") { pickApp { safelist.add($0) } }
                        Button("Reset to Panic Safelist") { safelist.resetFromPanicSafelist() }
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func appIcon(for bundleID: String) -> some View {
        if let icon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon {
            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.dashed").frame(width: 20, height: 20).foregroundColor(.secondary)
        }
    }

    private func pickApp(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Select App"
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty else { return }
        completion(id)
    }
}
