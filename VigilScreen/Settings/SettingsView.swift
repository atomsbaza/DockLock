import SwiftUI
import AppKit
import ServiceManagement

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case panicMode
    case proximity
    case shoulderSurfing
    case presentationMode
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .panicMode: "Panic Mode"
        case .proximity: "Proximity Lock"
        case .shoulderSurfing: "Shoulder Surfing"
        case .presentationMode: "Presentation Mode"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .panicMode: "eye.slash"
        case .proximity: "antenna.radiowaves.left.and.right"
        case .shoulderSurfing: "eye.trianglebadge.exclamationmark"
        case .presentationMode: "rectangle.on.rectangle"
        case .history: "clock"
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsSection? = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 190)

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Vigil Screen")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 8)

            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .general {
        case .general:
            SettingsDetailContainer(title: SettingsSection.general.title) {
                GeneralSettingsView()
            }
        case .panicMode:
            SettingsDetailContainer(title: SettingsSection.panicMode.title) {
                PanicModeView()
            }
        case .proximity:
            SettingsDetailContainer(title: SettingsSection.proximity.title) {
                ProximityView()
            }
        case .shoulderSurfing:
            SettingsDetailContainer(title: SettingsSection.shoulderSurfing.title) {
                ShoulderSurfingView()
            }
        case .presentationMode:
            SettingsDetailContainer(title: SettingsSection.presentationMode.title) {
                PresentationModeView()
            }
        case .history:
            SettingsDetailContainer(title: SettingsSection.history.title) {
                LockHistoryView()
            }
        }
    }
}

private struct SettingsDetailContainer<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var cloud = CloudSyncStore.shared

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        toggleLaunchAtLogin(enabled)
                    }
            }

            Section("Menu Bar") {
                Toggle("Show live Bluetooth stats", isOn: $settings.showMenuBarStats)
                if settings.showMenuBarStats {
                    Text("Displays signal strength (dBm) and countdown next to the menu bar icon when Proximity Lock is active.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Permissions") {
                HStack {
                    Label("Accessibility", systemImage: "accessibility")
                    Spacer()
                    if permissions.hasAccessibilityPermission {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    } else {
                        Button("Grant Access") {
                            permissions.requestAccessibilityIfNeeded()
                        }
                    }
                }
            }

            Section {
                HStack(alignment: .center) {
                    Label("Status", systemImage: "icloud")
                    Spacer()
                    if cloud.isSignedInToICloud {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Button("Open iCloud Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                if let last = cloud.lastSyncedAt {
                    HStack {
                        Text("Last synced")
                        Spacer()
                        Text(last, style: .relative)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
                Text(cloud.isSignedInToICloud
                     ? "Settings, app safelist, and lock history sync across Macs signed into the same iCloud account."
                     : "Sign into iCloud and enable iCloud Drive in System Settings to sync settings, safelist, and history across your Macs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("iCloud Sync")
            }

            Section("About") {
                if let privacyURL = URL(string: "https://github.com/atomsbaza/VigilScreen#privacy--security") {
                    Link(destination: privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
                if let issuesURL = URL(string: "https://github.com/atomsbaza/VigilScreen/issues") {
                    Link(destination: issuesURL) {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            settings.launchAtLogin = !enable // revert on failure
        }
    }
}
