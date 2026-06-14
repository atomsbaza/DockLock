import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AuditSummaryGenerator {
    static let shared = AuditSummaryGenerator()
    private init() {}

    // MARK: - Availability

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    // MARK: - Prompt construction (internal for tests)

    func buildPrompt(from events: [LockEvent]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let lines = events.map { event in
            "\(formatter.string(from: event.date)) — \(triggerLabel(for: event.trigger))"
        }.joined(separator: "\n")

        return lines.isEmpty
            ? "No events.\nSummarise this privacy session in 2–3 plain sentences."
            : "\(lines)\nSummarise this privacy session in 2–3 plain sentences."
    }

    // MARK: - Private

    private func triggerLabel(for trigger: LockTriggerType) -> String {
        switch trigger {
        case .proximity:               return "Proximity Lock engaged"
        case .panic:                   return "Panic Mode triggered"
        case .shoulderSurfer:          return "Shoulder surfer detected"
        case .intruderCapture:         return "Failed unlock attempt (intruder capture)"
        case .presentationMode:        return "Presentation Mode started"
        case .presentationModeRelease: return "Presentation Mode ended"
        }
    }
}
