import SwiftUI

struct ShoulderSurfingView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var detector = ShoulderSurfingDetector.shared

    var body: some View {
        Form {
            Section {
                Toggle("Detect shoulder surfing", isOn: $settings.shoulderSurfingEnabled)

                if detector.cameraPermissionDenied {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Camera access denied. Enable it in System Settings → Privacy & Security → Camera.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.shoulderSurfingEnabled && !detector.cameraPermissionDenied {
                    HStack {
                        Label("Sensitivity", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text("Low")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.shoulderSurfingSensitivity, in: 0...1)
                            .frame(width: 140)
                        Text("High")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Camera", systemImage: "camera.fill")
                        Spacer()
                        if detector.isRunning {
                            FaceCountBadge(count: detector.faceCount)
                        } else {
                            Text("Starting…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Detection")
            } footer: {
                Text("Camera runs on-device only. No images or data leave your Mac. Panic Mode triggers automatically when a second face is detected for more than ~1–3 seconds.")
                    .foregroundStyle(.secondary)
            }

            if settings.shoulderSurfingEnabled && !detector.cameraPermissionDenied {
                Section {
                    Toggle("Auto-release when threat is gone", isOn: $settings.shoulderSurfingAutoRelease)

                    if settings.shoulderSurfingAutoRelease {
                        HStack {
                            Label("Release delay", systemImage: "timer")
                            Spacer()
                            Text("3s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $settings.shoulderSurfingReleaseDelay, in: 3...30, step: 1)
                                .frame(width: 130)
                            Text("\(Int(settings.shoulderSurfingReleaseDelay))s")
                                .font(.caption)
                                .monospacedDigit()
                                .frame(width: 28, alignment: .leading)
                                .foregroundStyle(.secondary)
                        }

                        if detector.releaseCountdownActive {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Releasing automatically — no faces detected…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Auto-Release")
                } footer: {
                    Text("When enabled, Panic Mode releases automatically after the set delay once only your face is seen again. Touch ID is not required for auto-release.")
                        .foregroundStyle(.secondary)
                }
            }
            if settings.shoulderSurfingFalsePositiveCount >= 3 {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("3 false triggers detected — reduce sensitivity?")
                                .font(.body)
                            Text("Faces on screens, TVs, or mirrors may be causing false alarms.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button("Reduce Sensitivity") {
                            settings.shoulderSurfingSensitivity = max(0.0, settings.shoulderSurfingSensitivity - 0.25)
                            settings.shoulderSurfingFalsePositiveCount = 0
                        }
                        Spacer()
                        Button("Dismiss") {
                            settings.shoulderSurfingFalsePositiveCount = 0
                        }
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Sensitivity Suggestion")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Shoulder Surfing")
    }
}

// MARK: - Face count badge

private struct FaceCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(count >= 2 ? Color.red : Color.green)
                .frame(width: 8, height: 8)
            Text(count == 0 ? "No faces" : count == 1 ? "1 face" : "\(count) faces")
                .font(.caption)
                .foregroundStyle(count >= 2 ? .red : .secondary)
                .monospacedDigit()
        }
        .animation(.easeInOut(duration: 0.2), value: count)
    }
}
