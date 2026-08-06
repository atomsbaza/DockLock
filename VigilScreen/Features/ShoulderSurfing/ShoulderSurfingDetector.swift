@preconcurrency import AVFoundation
import Vision
import Combine

/// Pure counter that decides when consecutive multi-face frames should trigger a panic.
struct ShoulderSurfingTrigger {
    var consecutiveFrames: Int = 0

    /// Number of consecutive ≥2-face frames required before triggering.
    /// sensitivity 0.0 → 2 frames (~1 s at 2 fps); 1.0 → 6 frames (~3 s).
    static func threshold(sensitivity: Double) -> Int {
        Int(2 + sensitivity * 4)
    }

    /// Feed one frame's face count. Returns `true` exactly once when the threshold is crossed.
    /// Resets the counter on both trigger and on count dropping below 2.
    mutating func process(faceCount: Int, threshold: Int) -> Bool {
        if faceCount >= 2 {
            consecutiveFrames += 1
            if consecutiveFrames >= threshold {
                consecutiveFrames = 0
                return true
            }
        } else {
            consecutiveFrames = 0
        }
        return false
    }
}

/// Monitors the front camera for a second face and auto-triggers Panic Mode.
/// Uses VNDetectFaceRectanglesRequest at ~2 fps; all processing is on-device.
@MainActor
final class ShoulderSurfingDetector: NSObject, ObservableObject {
    static let shared = ShoulderSurfingDetector()

    @Published private(set) var isRunning = false
    @Published private(set) var faceCount = 0
    @Published private(set) var cameraPermissionDenied = false
    /// True while the auto-release countdown is ticking.
    @Published private(set) var releaseCountdownActive = false

    private var session: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let visionQueue = DispatchQueue(label: "com.vigilscreen.shouldersurfing", qos: .userInitiated)
    private var trigger = ShoulderSurfingTrigger()
    private var cancellables = Set<AnyCancellable>()
    // Accessed only from visionQueue — nonisolated(unsafe) is correct here.
    nonisolated(unsafe) private var lastProcessedTime = CMTime.zero

    /// Set when we were the ones who triggered panic; allows auto-release.
    private var didAutoTrigger = false
    private var releaseTask: Task<Void, Never>?

    private var triggerThreshold: Int {
        ShoulderSurfingTrigger.threshold(sensitivity: SettingsStore.shared.shoulderSurfingSensitivity)
    }

    private override init() {
        super.init()

        SettingsStore.shared.$shoulderSurfingEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled { self?.requestPermissionAndStart() } else { self?.stop() }
            }
            .store(in: &cancellables)

        // When panic ends (manually or via auto-release), reset auto-trigger state.
        PanicModeManager.shared.$isActive
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                guard let self else { return }
                if !active {
                    // Panic was released — reset state and resume detection.
                    self.didAutoTrigger = false
                    self.cancelReleaseCountdown()
                    if SettingsStore.shared.shoulderSurfingEnabled {
                        self.requestPermissionAndStart()
                    }
                }
                // When panic becomes active we keep the session running
                // (needed for auto-release to see when faces drop back to ≤1).
            }
            .store(in: &cancellables)

        if SettingsStore.shared.shoulderSurfingEnabled {
            requestPermissionAndStart()
        }
    }

    // MARK: - Permission + lifecycle

    func requestPermissionAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startSession()
                    } else {
                        self?.cameraPermissionDenied = true
                    }
                }
            }
        default:
            cameraPermissionDenied = true
        }
    }

    private func startSession() {
        guard session == nil else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        let s = AVCaptureSession()
        s.sessionPreset = .medium

        guard s.canAddInput(input) else { return }
        s.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: visionQueue)
        guard s.canAddOutput(output) else { return }
        s.addOutput(output)

        session = s
        videoOutput = output
        trigger = ShoulderSurfingTrigger()

        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
        isRunning = true
        cameraPermissionDenied = false
    }

    func stop() {
        cancelReleaseCountdown()
        guard let s = session else { return }
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
        session = nil
        videoOutput = nil
        isRunning = false
        faceCount = 0
        trigger = ShoulderSurfingTrigger()
        didAutoTrigger = false
    }

    // MARK: - Auto-release countdown

    private func startReleaseCountdownIfNeeded() {
        guard releaseTask == nil else { return }
        releaseCountdownActive = true
        let delay = SettingsStore.shared.shoulderSurfingReleaseDelay
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.releaseTask = nil
            self.releaseCountdownActive = false
            self.didAutoTrigger = false
            PanicModeManager.shared.releasePanicWithoutAuth()
        }
    }

    private func cancelReleaseCountdown() {
        releaseTask?.cancel()
        releaseTask = nil
        releaseCountdownActive = false
    }

    // MARK: - Trigger + release logic (MainActor)

    private func handleFaceCount(_ count: Int) {
        faceCount = count
        let panicActive = PanicModeManager.shared.isActive

        if panicActive {
            // Only watch for auto-release if we triggered this panic and the feature is on.
            if didAutoTrigger && SettingsStore.shared.shoulderSurfingAutoRelease {
                if count <= 1 {
                    startReleaseCountdownIfNeeded()
                } else {
                    // Surfer is still/back — cancel countdown.
                    cancelReleaseCountdown()
                }
            }
            return
        }

        // Not in panic — watch for a shoulder surfer.
        cancelReleaseCountdown()
        didAutoTrigger = false

        if trigger.process(faceCount: count, threshold: triggerThreshold) {
            didAutoTrigger = true
            LockHistoryStore.shared.record(.shoulderSurfer)
            PanicModeManager.shared.triggerPanic()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ShoulderSurfingDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                    didOutput sampleBuffer: CMSampleBuffer,
                                    from connection: AVCaptureConnection) {
        // Throttle to ~2 fps
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let elapsed = CMTimeGetSeconds(CMTimeSubtract(pts, lastProcessedTime))
        guard elapsed >= 0.5 else { return }
        lastProcessedTime = pts

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                             orientation: .up,
                                             options: [:])
        try? handler.perform([request])
        let count = request.results?.count ?? 0

        Task { @MainActor in self.handleFaceCount(count) }
    }
}
