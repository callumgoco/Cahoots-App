import AVFoundation
import Foundation
import UIKit

protocol WorkoutCapturing: AnyObject {
    var previewLayer: AVCaptureVideoPreviewLayer? { get }
    var isUsingStub: Bool { get }
    var isRecording: Bool { get }
    var currentPosition: AVCaptureDevice.Position { get }
    func prepare() async throws
    func flipCamera() async throws
    func startRecording(to url: URL) async throws
    func stopRecording() async throws -> TimeInterval
    func tearDown()
}

enum WorkoutCaptureError: LocalizedError {
    case permissionDenied
    case unavailable
    case alreadyRecording
    case notRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied: String(localized: "Camera access is required to log a workout and unlock the crew feed.")
        case .unavailable: String(localized: "The camera is unavailable right now.")
        case .alreadyRecording: String(localized: "Already recording.")
        case .notRecording: String(localized: "Nothing is recording.")
        }
    }
}

@MainActor
final class StubWorkoutCaptureController: WorkoutCapturing {
    var previewLayer: AVCaptureVideoPreviewLayer? { nil }
    var isUsingStub: Bool { true }
    private(set) var isRecording = false
    private(set) var currentPosition: AVCaptureDevice.Position = .front
    private var startedAt: Date?

    func prepare() async throws {}

    func flipCamera() async throws {
        currentPosition = currentPosition == .front ? .back : .front
    }

    func startRecording(to url: URL) async throws {
        guard !isRecording else { throw WorkoutCaptureError.alreadyRecording }
        isRecording = true
        startedAt = .now
        try Data("stub-workout-clip".utf8).write(to: url)
    }

    func stopRecording() async throws -> TimeInterval {
        guard isRecording else { throw WorkoutCaptureError.notRecording }
        isRecording = false
        let duration = Date().timeIntervalSince(startedAt ?? .now)
        startedAt = nil
        // Stub always produces a valid ≥2s clip for UI tests.
        return max(2.5, duration)
    }

    func tearDown() {
        isRecording = false
        startedAt = nil
    }
}

@MainActor
final class WorkoutCaptureController: NSObject, WorkoutCapturing, AVCaptureFileOutputRecordingDelegate {
    var previewLayer: AVCaptureVideoPreviewLayer?
    var isUsingStub: Bool { false }
    private(set) var isRecording = false
    private(set) var currentPosition: AVCaptureDevice.Position = .front

    // Configured on the main actor, but started off it so the blocking
    // startRunning() call never stalls the UI.
    nonisolated(unsafe) private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var continuation: CheckedContinuation<TimeInterval, Error>?
    private var recordingStartedAt: Date?
    private var maxDurationTimer: Timer?

    static var shouldUseStub: Bool {
        if ProcessInfo.processInfo.arguments.contains("-stubWorkoutCapture") { return true }
        if ProcessInfo.processInfo.arguments.contains("-showCheckIn") { return true }
        #if targetEnvironment(simulator)
        return true
        #else
        return ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
        #endif
    }

    static func make() -> any WorkoutCapturing {
        if shouldUseStub { return StubWorkoutCaptureController() }
        return WorkoutCaptureController()
    }

    func prepare() async throws {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if videoStatus == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .video) else { throw WorkoutCaptureError.permissionDenied }
        }
        if audioStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw WorkoutCaptureError.permissionDenied
        }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let videoInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(videoInput) else {
            session.commitConfiguration()
            throw WorkoutCaptureError.unavailable
        }
        session.addInput(videoInput)

        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        guard session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            throw WorkoutCaptureError.unavailable
        }
        session.addOutput(movieOutput)
        if let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
                continuation.resume()
            }
        }
    }

    func flipCamera() async throws {
        currentPosition = currentPosition == .front ? .back : .front
        guard !isRecording else { return }
        session.beginConfiguration()
        if let current = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) }) {
            session.removeInput(current)
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            throw WorkoutCaptureError.unavailable
        }
        session.addInput(input)
        session.commitConfiguration()
    }

    func startRecording(to url: URL) async throws {
        guard !isRecording else { throw WorkoutCaptureError.alreadyRecording }
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        isRecording = true
        recordingStartedAt = .now
        movieOutput.startRecording(to: url, recordingDelegate: self)
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: WorkoutClipRules.maximumDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                _ = try? await self?.stopRecording()
            }
        }
    }

    func stopRecording() async throws -> TimeInterval {
        guard isRecording else { throw WorkoutCaptureError.notRecording }
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            movieOutput.stopRecording()
        }
    }

    func tearDown() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        if session.isRunning { session.stopRunning() }
        previewLayer = nil
        isRecording = false
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            let duration = Date().timeIntervalSince(self.recordingStartedAt ?? .now)
            self.recordingStartedAt = nil
            if let error {
                self.continuation?.resume(throwing: error)
            } else {
                self.continuation?.resume(returning: min(duration, WorkoutClipRules.maximumDuration))
            }
            self.continuation = nil
        }
    }
}
