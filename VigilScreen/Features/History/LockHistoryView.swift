import SwiftUI

struct LockHistoryView: View {
    @ObservedObject private var history = LockHistoryStore.shared
    @State private var showingClearConfirm = false
    @State private var selectedPhoto: URL?

    // Internal (not private) so SummarySheet at file scope can reference it.
    enum SummaryState: Equatable {
        case idle, loading, result(String), failed
    }
    @State private var summaryState: SummaryState = .idle

    var body: some View {
        Group {
            if history.events.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
        .navigationTitle("History")
        .sheet(item: $selectedPhoto) { url in
            PhotoDetailSheet(photoURL: url)
        }
        .sheet(isPresented: Binding(
            get: { summaryState != .idle },
            set: { if !$0 { summaryState = .idle } }
        )) {
            SummarySheet(state: summaryState) { summaryState = .idle }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No events yet")
                .font(.headline)
            Text("Lock events from Proximity Lock and Panic Mode will appear here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Event list

    private var eventList: some View {
        List(history.events) { event in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: iconName(for: event.trigger))
                        .font(.system(size: 14))
                        .foregroundColor(iconColor(for: event.trigger))
                        .frame(width: 24)

                    // Label + relative time
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(for: event.trigger))
                            .font(.body)
                        Text(event.date, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Intruder photo thumbnail
                    if let url = history.photoURL(for: event) {
                        photoThumbnail(url: url)
                    }

                    // Formatted date
                    Text(event.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if event.trigger == .shoulderSurfer {
                    Button("Not a real threat") {
                        ShoulderSurfingDetector.shared.recordFalsePositive()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .padding(.leading, 36)
                }
            }
            .padding(.vertical, 2)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Clear") { showingClearConfirm = true }
                    .foregroundColor(.red)
            }
            if AuditSummaryGenerator.shared.isAvailable {
                ToolbarItem(placement: .automatic) {
                    summarizeButton
                }
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $showingClearConfirm) {
            Button("Clear All", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var summarizeButton: some View {
        if summaryState == .loading {
            ProgressView()
                .scaleEffect(0.7)
        } else {
            Button("Summarize session") {
                guard summaryState != .loading else { return }
                summaryState = .loading
                let events = history.events
                Task { @MainActor in
                    if #available(macOS 26, *) {
                        do {
                            let text = try await AuditSummaryGenerator.shared.generate(from: events)
                            summaryState = .result(text)
                        } catch {
                            summaryState = .failed
                        }
                    } else {
                        summaryState = .failed
                    }
                }
            }
            .disabled(history.events.isEmpty)
        }
    }

    @ViewBuilder
    private func photoThumbnail(url: URL) -> some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.4), lineWidth: 1))
                .onTapGesture { selectedPhoto = url }
                .help("Tap to view captured photo")
        }
    }

    // MARK: - Helpers

    private func iconName(for trigger: LockTriggerType) -> String {
        switch trigger {
        case .proximity:       return "antenna.radiowaves.left.and.right"
        case .panic:           return "eye.slash"
        case .intruderCapture: return "person.fill.questionmark"
        case .shoulderSurfer:  return "eye.trianglebadge.exclamationmark"
        case .presentationMode: return "rectangle.on.rectangle"
        case .presentationModeRelease: return "rectangle.on.rectangle"
        }
    }

    private func iconColor(for trigger: LockTriggerType) -> Color {
        switch trigger {
        case .proximity:       return .blue
        case .panic:           return .red
        case .intruderCapture: return .orange
        case .shoulderSurfer:  return .purple
        case .presentationMode: return .green
        case .presentationModeRelease: return .green.opacity(0.6)
        }
    }

    private func label(for trigger: LockTriggerType) -> String {
        switch trigger {
        case .proximity:       return "Proximity Lock"
        case .panic:           return "Panic Mode"
        case .intruderCapture: return "Failed Unlock Attempt"
        case .shoulderSurfer:  return "Shoulder Surfing Detected"
        case .presentationMode: return "Presentation Mode"
        case .presentationModeRelease: return "Presentation Mode Ended"
        }
    }
}

// MARK: - Photo detail sheet

private struct PhotoDetailSheet: View {
    let photoURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Intruder Capture")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            if let image = NSImage(contentsOf: photoURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                Text("Photo unavailable")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - Summary sheet

private struct SummarySheet: View {
    let state: LockHistoryView.SummaryState
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Session Summary")
                    .font(.headline)
                Spacer()
                Button("Done") { onDismiss() }
            }

            Divider()

            switch state {
            case .idle, .loading:
                ProgressView("Generating summary…")
                    .frame(maxWidth: .infinity, alignment: .center)
            case .result(let text):
                Text(text)
                    .font(.body)
            case .failed:
                Text("Summary unavailable — try again.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(width: 420, height: 200)
    }
}

// MARK: - URL: Identifiable for .sheet(item:)

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
