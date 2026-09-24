import AVFoundation
import Foundation
import OSLog
import UIKit

protocol WorkoutCapturing: AnyObject {
    var captureSession: AVCaptureSession? { get }
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
        case .permissionDenied: String(localized: "Camera access is needed to film a clip. You can skip recording and enter today’s amount.")
        case .unavailable: String(localized: "The camera is unavailable right now.")
        case .alreadyRecording: String(localized: "Already recording.")
        case .notRecording: String(localized: "Nothing is recording.")
        }
    }
}

@MainActor
final class StubWorkoutCaptureController: WorkoutCapturing {
    var captureSession: AVCaptureSession? { nil }
    var isUsingStub: Bool { true }
    private(set) var isRecording = false
    private(set) var currentPosition: AVCaptureDevice.Position = .front
    private var startedAt: Date?
    /// Counts how many times `prepare()` ran — used by unit tests for reuse behaviour.
    private(set) var prepareCallCount = 0
    /// Optional delay so concurrent prepare callers overlap in tests.
    var prepareDelayNanoseconds: UInt64 = 0

    func prepare() async throws {
        prepareCallCount += 1
        if prepareDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: prepareDelayNanoseconds)
        }
    }

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

/// Owns the AVCaptureSession on a dedicated serial queue so configuration and
/// `startRunning` never block the main actor. Preview setup is video-only.
/// Microphone and stabilization are added when recording starts.
@MainActor
final class WorkoutCaptureController: NSObject, WorkoutCapturing, AVCaptureFileOutputRecordingDelegate {
    var captureSession: AVCaptureSession? { graph.session }
    var isUsingStub: Bool { false }
    private(set) var isRecording = false
    private(set) var currentPosition: AVCaptureDevice.Position = .front

    private let sessionQueue = DispatchQueue(label: "com.callumoconnor.cahoots.workout-capture", qos: .userInitiated)
    /// Session graph lives only on `sessionQueue`.
    private let graph = CaptureGraph()
    private var continuation: CheckedContinuation<TimeInterval, Error>?
    private var recordingStartedAt: Date?

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
            AppLog.capture.error("Capture prepare denied. videoAuth=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue, privacy: .public)")
            throw WorkoutCaptureError.permissionDenied
        }

        let position = currentPosition
        AppLog.capture.info("Capture session configuring. position=\(position == .front ? "front" : "back", privacy: .public) videoOnly=true")
        let graph = self.graph
        let started = ProcessInfo.processInfo.systemUptime

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try graph.prepareForPreview(position: position)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let elapsed = Int(((ProcessInfo.processInfo.systemUptime - started) * 1000).rounded())
        AppLog.capture.info("Capture session ready. running=\(graph.session.isRunning, privacy: .public) configureMs=\(elapsed, privacy: .public)")
    }

    func flipCamera() async throws {
        let next = currentPosition == .front ? AVCaptureDevice.Position.back : .front
        guard !isRecording else { return }
        let graph = self.graph

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try graph.flip(to: next)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        currentPosition = next
    }

    func startRecording(to url: URL) async throws {
        guard !isRecording else { throw WorkoutCaptureError.alreadyRecording }
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        let audioAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let graph = self.graph
        let started = ProcessInfo.processInfo.systemUptime
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                graph.enableRecordingExtras(audioAuthorized: audioAuthorized)
                continuation.resume()
            }
        }
        AppLog.capture.info("Recording extras ready. audio=\(audioAuthorized, privacy: .public) ms=\(Int(((ProcessInfo.processInfo.systemUptime - started) * 1000).rounded()), privacy: .public)")

        isRecording = true
        recordingStartedAt = .now
        graph.movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording() async throws -> TimeInterval {
        guard isRecording else { throw WorkoutCaptureError.notRecording }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            graph.movieOutput.stopRecording()
        }
    }

    func tearDown() {
        isRecording = false
        let graph = self.graph
        sessionQueue.async {
            graph.tearDown()
        }
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

/// Capture graph mutated only on the workout-capture session queue.
private final class CaptureGraph: @unchecked Sendable {
    let session = AVCaptureSession()
    let movieOutput = AVCaptureMovieFileOutput()
    private var isConfigured = false

    func prepareForPreview(position: AVCaptureDevice.Position) throws {
        session.automaticallyConfiguresApplicationAudioSession = false

        if !isConfigured || !session.isRunning {
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let videoInput = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(videoInput) else {
                session.commitConfiguration()
                throw WorkoutCaptureError.unavailable
            }
            session.addInput(videoInput)

            guard session.canAddOutput(movieOutput) else {
                session.commitConfiguration()
                throw WorkoutCaptureError.unavailable
            }
            session.addOutput(movieOutput)
            session.commitConfiguration()
            isConfigured = true
        }

        if !session.isRunning {
            session.startRunning()
        }
    }

    /// Mic and stabilization are applied only once recording begins so preview startup stays light.
    func enableRecordingExtras(audioAuthorized: Bool) {
        session.beginConfiguration()
        if audioAuthorized,
           !session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }) {
            do {
                try configureAudioSession()
                if let mic = AVCaptureDevice.default(for: .audio),
                   let audioInput = try? AVCaptureDeviceInput(device: mic),
                   session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            } catch {
                AppLog.capture.error("Recording will continue without audio. \(error.localizedDescription, privacy: .public)")
            }
        }
        if let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .standard
        }
        session.commitConfiguration()
    }

    func flip(to position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        if let current = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) }) {
            session.removeInput(current)
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            throw WorkoutCaptureError.unavailable
        }
        session.addInput(input)
        session.commitConfiguration()
    }

    func tearDown() {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
        isConfigured = false
    }

    private func configureAudioSession() throws {
        let audio = AVAudioSession.sharedInstance()
        // Same option bit. Xcode 26 renamed allowBluetooth to allowBluetoothHFP;
        // Xcode 16.4, which CI uses, only has allowBluetooth.
        #if compiler(>=6.2)
        let bluetooth = AVAudioSession.CategoryOptions.allowBluetoothHFP
        #else
        let bluetooth = AVAudioSession.CategoryOptions.allowBluetooth
        #endif
        try audio.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, bluetooth])
        try audio.setActive(true, options: [])
    }
}
