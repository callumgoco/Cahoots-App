import AVFoundation
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class WorkoutSessionController {
    var phase: WorkoutSessionPhase = .choose
    var capture: (any WorkoutCapturing)?
    /// Published when preview warmup finishes so the camera view can attach before Record.
    var captureSession: AVCaptureSession?
    var cameraPosition: AVCaptureDevice.Position = .front
    var usesStubCapture = false
    var isCaptureReady = false
    var isActivelyRecording = false
    var recordedClips: [WorkoutClip] = []
    var currentKind: WorkoutClipKind = .set
    var recordingElapsed: TimeInterval = 0
    var previewURL: URL?
    var amount: Double = 0
    var isSubmitting = false
    var submittedPoints: Int?
    var submittedSyncState: SyncState?
    var formError: String?
    var showHighConfirmation = false
    var captureError: String?
    var sessionRequirementDate: Date?
    var openedWhileWindowOpen = false
    /// True when a start clip is already saved and Record should open the finish-clip step.
    var hasPendingStartClip = false
    /// Override in unit tests to inject a capture double.
    var captureFactory: () -> any WorkoutCapturing = { WorkoutCaptureController.make() }

    private var recordingTimer: Timer?
    /// In-flight camera warm-up so Record can reuse a session started during bootstrap.
    private var prepareTask: Task<Void, Never>?
    private var prepareGeneration = 0

    var canStartCaptureActions: Bool {
        openedWhileWindowOpen && isCaptureReady
    }

    var clipDurationLabel: String {
        guard let last = recordedClips.last else { return "" }
        return String(localized: "\(Int(last.durationSeconds.rounded())) seconds")
    }

    var recordHint: String {
        switch currentKind {
        case .set: String(localized: "Film your set")
        case .start: String(localized: "Start clip")
        case .finish: String(localized: "Finish clip")
        }
    }

    var navigationTitle: String {
        switch phase {
        case .reveal: String(localized: "Crew reveal")
        case .confirm: String(localized: "Confirm amount")
        case .waitingForFinish: String(localized: "Start clip saved")
        default: String(localized: "Log workout")
        }
    }

    var dismissLabel: String {
        phase == .waitingForFinish ? String(localized: "Finish later") : String(localized: "Close")
    }

    var showsCameraPreview: Bool {
        switch phase {
        case .prep, .countdown, .record: true
        default: false
        }
    }

    /// Keeps the preview in the hierarchy on the choose screen so the capture connection
    /// is already live when Record is tapped.
    var keepsCameraMounted: Bool {
        switch phase {
        case .choose, .prep, .countdown, .record:
            captureSession != nil || usesStubCapture
        default:
            false
        }
    }

    func bootstrap(store: AppStore) {
        guard let challenge = store.currentChallenge else { return }
        amount = max(challenge.minimumQuantity, previousAmount(store: store, challenge: challenge) ?? 0)
        let now = store.environment.clock.now
        if let userID = store.currentUser?.id,
           let pending = PendingWorkoutSessionStore.load(challengeID: challenge.id, userID: userID) {
            recordedClips = []
            currentKind = .finish
            sessionRequirementDate = pending.requirementDate
            openedWhileWindowOpen = true
            hasPendingStartClip = true
            phase = .choose
            beginCameraWarmUpIfNeeded()
            return
        }
        sessionRequirementDate = ScheduleEngine.requirementDay(for: now, challenge: challenge) ?? now
        openedWhileWindowOpen = CheckInSubmissionRules.isWindowOpen(challenge: challenge, at: now)
        if !openedWhileWindowOpen {
            formError = CheckInSubmissionRules.closedWindowMessage
        }
        currentKind = challenge.measurementType.requiresTwoClips ? .start : .set
        hasPendingStartClip = false
        phase = .choose
        beginCameraWarmUpIfNeeded()
    }

    /// Continues into the camera flow, or the finish-clip step when a start clip is already saved.
    func chooseRecord(store: AppStore) {
        guard openedWhileWindowOpen else { return }
        formError = nil
        if hasPendingStartClip,
           let challenge = store.currentChallenge,
           let userID = store.currentUser?.id,
           let pending = PendingWorkoutSessionStore.load(challengeID: challenge.id, userID: userID) {
            recordedClips = [pending.startClip]
            currentKind = .finish
            sessionRequirementDate = pending.requirementDate
            phase = .waitingForFinish
            return
        }
        currentKind = store.currentChallenge?.measurementType.requiresTwoClips == true ? .start : .set
        phase = .prep
        CaptureTiming.markRecordTapped()
        AppLog.capture.info("Record tapped. Opening prep. kind=\(String(describing: self.currentKind), privacy: .public) captureReady=\(self.isCaptureReady, privacy: .public) preview=\(self.captureSession == nil ? "nil" : "set", privacy: .public)")
        CaptureTiming.logSinceRecord("phase set to prep")
        Task { await prepareCapture() }
    }

    /// Opens the amount screen with no clips. A saved start clip stays on disk until submit or Record.
    func skipRecording() {
        guard openedWhileWindowOpen else { return }
        formError = nil
        recordedClips = []
        tearDown()
        phase = .confirm
    }

    func tearDown() {
        AppLog.capture.info("Capture tear down. phase=\(String(describing: self.phase), privacy: .public)")
        prepareTask?.cancel()
        prepareTask = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        isCaptureReady = false
        isActivelyRecording = false
        captureSession = nil
        usesStubCapture = false
        capture?.tearDown()
        capture = nil
    }

    /// Starts camera warm-up while the user is still on the choose screen.
    func beginCameraWarmUpIfNeeded() {
        guard openedWhileWindowOpen, !isCaptureReady else {
            AppLog.capture.info("Camera warm-up skipped. windowOpen=\(self.openedWhileWindowOpen, privacy: .public) captureReady=\(self.isCaptureReady, privacy: .public)")
            return
        }
        AppLog.capture.info("Camera warm-up started")
        CaptureTiming.markWarmUp()
        Task { await prepareCapture() }
    }

    func prepareCapture() async {
        if isCaptureReady, capture != nil {
            AppLog.capture.info("Prepare skipped. Capture already ready.")
            CaptureTiming.logSinceRecord("prepare skipped")
            return
        }
        if let inFlight = prepareTask {
            AppLog.capture.info("Prepare joined in-flight warm-up")
            await inFlight.value
            if isCaptureReady, capture != nil { return }
        }

        prepareGeneration += 1
        let generation = prepareGeneration
        let work = Task { @MainActor in
            await self.performPrepare()
        }
        prepareTask = work
        await work.value
        if prepareGeneration == generation {
            prepareTask = nil
        }
    }

    private func performPrepare() async {
        isCaptureReady = false
        captureError = nil

        let controller: any WorkoutCapturing
        if let existing = capture {
            controller = existing
        } else {
            controller = captureFactory()
            capture = controller
        }

        AppLog.capture.info("Prepare running. stub=\(controller.isUsingStub, privacy: .public) phase=\(String(describing: self.phase), privacy: .public)")
        do {
            try await controller.prepare()
            guard !Task.isCancelled else {
                AppLog.capture.info("Prepare cancelled after session setup")
                return
            }
            captureError = nil
            captureSession = controller.captureSession
            cameraPosition = controller.currentPosition
            usesStubCapture = controller.isUsingStub
            isCaptureReady = true
            AppLog.capture.info("Prepare ready. preview=\(self.captureSession == nil ? "nil" : "set", privacy: .public) sessionID=\(PreviewDebug.id(self.captureSession), privacy: .public) sessionRunning=\(self.captureSession?.isRunning ?? false, privacy: .public) stub=\(self.usesStubCapture, privacy: .public) position=\(self.cameraPosition == .front ? "front" : "back", privacy: .public) phase=\(String(describing: self.phase), privacy: .public)")
            CaptureTiming.logSinceWarmUp("prepare ready")
            CaptureTiming.logSinceRecord("prepare ready")
        } catch WorkoutCaptureError.permissionDenied {
            guard !Task.isCancelled else { return }
            isCaptureReady = false
            AppLog.capture.error("Prepare failed. Camera permission denied. phase=\(String(describing: self.phase), privacy: .public)")
            if phase == .prep || phase == .choose {
                phase = .permissionDenied
            }
        } catch {
            guard !Task.isCancelled else { return }
            isCaptureReady = false
            captureError = error.localizedDescription
            AppLog.capture.error("Prepare failed. \(error.localizedDescription, privacy: .public)")
        }
    }

    func beginCountdown(reduceMotion: Bool) {
        guard canStartCaptureActions else {
            AppLog.capture.info("Start tapped but capture is not ready. windowOpen=\(self.openedWhileWindowOpen, privacy: .public) captureReady=\(self.isCaptureReady, privacy: .public) preview=\(self.captureSession == nil ? "nil" : "set", privacy: .public)")
            return
        }
        if reduceMotion {
            AppLog.capture.info("Start tapped. Reduce Motion skips countdown.")
            beginAutoRecording()
            return
        }
        AppLog.capture.info("Start tapped. Countdown beginning. preview=\(self.captureSession == nil ? "nil" : "set", privacy: .public)")
        phase = .countdown(3)
        Task {
            for next in stride(from: 3, through: 1, by: -1) {
                guard case .countdown = phase else { return }
                phase = .countdown(next)
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            guard case .countdown = phase else { return }
            phase = .countdown(0)
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard case .countdown = phase else { return }
            beginAutoRecording()
        }
    }

    /// Moves into the record phase and starts capture immediately (countdown finished or skipped).
    func beginAutoRecording() {
        guard canStartCaptureActions, !isActivelyRecording else {
            AppLog.capture.info("Auto-record skipped. captureReady=\(self.isCaptureReady, privacy: .public) alreadyRecording=\(self.isActivelyRecording, privacy: .public)")
            return
        }
        AppLog.capture.info("Auto-record starting")
        formError = nil
        recordingElapsed = 0
        isActivelyRecording = true
        phase = .record
        Task { await startRecording() }
    }

    func startRecording() async {
        guard let capture, isCaptureReady else {
            AppLog.capture.info("startRecording skipped. capture=\(self.capture == nil ? "nil" : "set", privacy: .public) captureReady=\(self.isCaptureReady, privacy: .public)")
            return
        }
        guard !capture.isRecording else {
            AppLog.capture.info("startRecording skipped. Capture is already recording.")
            return
        }
        isActivelyRecording = true
        let filename = WorkoutClipStore.makeFilename(kind: currentKind)
        let url = WorkoutClipStore.fileURL(for: filename)
        do {
            AppLog.capture.info("startRecording file=\(filename, privacy: .public)")
            try await capture.startRecording(to: url)
            previewURL = url
            AppLog.capture.info("Recording started")
            recordingElapsed = 0
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.recordingElapsed += 0.25
                    if self.recordingElapsed >= WorkoutClipRules.maximumDuration {
                        await self.stopRecording()
                    }
                }
            }
        } catch WorkoutCaptureError.alreadyRecording {
            AppLog.capture.info("startRecording reported already recording")
            isActivelyRecording = true
        } catch {
            isActivelyRecording = false
            formError = error.localizedDescription
            phase = .prep
            AppLog.capture.error("startRecording failed. \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopRecording() async {
        recordingTimer?.invalidate()
        recordingTimer = nil
        guard let capture else { return }
        do {
            let duration = try await capture.stopRecording()
            isActivelyRecording = false
            AppLog.capture.info("Recording stopped. duration=\(duration, privacy: .public)s")
            let filename = previewURL?.lastPathComponent ?? WorkoutClipStore.makeFilename(kind: currentKind)
            if duration < WorkoutClipRules.minimumDuration {
                formError = String(localized: "Clips must be at least 2 seconds.")
                recordedClips.removeAll { $0.kind == currentKind }
                phase = .review
                let clip = WorkoutClip(id: UUID(), kind: currentKind, durationSeconds: duration, localFilename: filename, remotePath: nil, createdAt: .now)
                recordedClips.removeAll { $0.kind == currentKind }
                recordedClips.append(clip)
                return
            }
            let clip = WorkoutClip(id: UUID(), kind: currentKind, durationSeconds: duration, localFilename: filename, remotePath: nil, createdAt: .now)
            recordedClips.removeAll { $0.kind == currentKind }
            recordedClips.append(clip)
            formError = nil
            phase = .review
        } catch {
            isActivelyRecording = false
            formError = error.localizedDescription
            phase = .prep
            AppLog.capture.error("stopRecording failed. \(error.localizedDescription, privacy: .public)")
        }
    }

    func acceptCurrentClip(store: AppStore) {
        guard let challenge = store.currentChallenge,
              let last = recordedClips.last,
              last.durationSeconds >= WorkoutClipRules.minimumDuration else {
            formError = String(localized: "Clips must be at least 2 seconds.")
            return
        }
        if challenge.measurementType.requiresTwoClips, currentKind == .start, let userID = store.currentUser?.id {
            let requirementDate = sessionRequirementDate
                ?? ScheduleEngine.requirementDay(for: store.environment.clock.now, challenge: challenge)
                ?? .now
            PendingWorkoutSessionStore.save(.init(
                challengeID: challenge.id, userID: userID, requirementDate: requirementDate,
                startClip: last, updatedAt: .now
            ))
            store.notePendingWorkoutSessionChanged()
            phase = .waitingForFinish
            return
        }
        if challenge.measurementType.requiresTwoClips, currentKind == .finish {
            phase = .confirm
            return
        }
        phase = .confirm
    }

    func retake() {
        if let filename = recordedClips.first(where: { $0.kind == currentKind })?.localFilename {
            try? FileManager.default.removeItem(at: WorkoutClipStore.fileURL(for: filename))
        }
        recordedClips.removeAll { $0.kind == currentKind }
        previewURL = nil
        formError = nil
        isActivelyRecording = false
        recordingElapsed = 0
        phase = .record
    }

    func recordFinishClip(store: AppStore) {
        currentKind = .finish
        phase = .prep
        Task { await prepareCapture() }
    }

    func discardStartClip(store: AppStore) {
        if let challenge = store.currentChallenge, let userID = store.currentUser?.id {
            PendingWorkoutSessionStore.clear(challengeID: challenge.id, userID: userID)
            store.notePendingWorkoutSessionChanged()
        }
        recordedClips = []
        hasPendingStartClip = false
        currentKind = store.currentChallenge?.measurementType.requiresTwoClips == true ? .start : .set
        tearDown()
        phase = .choose
        beginCameraWarmUpIfNeeded()
    }

    func requestSubmit(store: AppStore) {
        if let challenge = store.currentChallenge, amount >= challenge.minimumQuantity * 5 {
            showHighConfirmation = true
        } else {
            Task { await submit(store: store) }
        }
    }

    func submit(store: AppStore) async {
        guard store.currentChallenge != nil else { return }
        guard openedWhileWindowOpen else {
            formError = CheckInSubmissionRules.closedWindowMessage
            return
        }
        isSubmitting = true
        formError = nil
        let result = await store.logWorkout(
            quantity: amount,
            clips: recordedClips,
            sessionRequirementDate: sessionRequirementDate,
            openedWhileWindowOpen: openedWhileWindowOpen
        )
        switch result {
        case .saved(let points, let syncState):
            submittedSyncState = syncState
            submittedPoints = points
            phase = .reveal
        case .validationFailed(let message), .persistenceFailed(let message):
            formError = message
        }
        isSubmitting = false
    }

    func flipCamera() async {
        do {
            try await capture?.flipCamera()
            if let capture {
                cameraPosition = capture.currentPosition
            }
            AppLog.capture.info("Camera flipped. position=\(self.cameraPosition == .front ? "front" : "back", privacy: .public)")
        } catch {
            AppLog.capture.error("Camera flip failed. \(error.localizedDescription, privacy: .public)")
        }
    }

    func adjustAmount(_ change: Double) {
        amount = max(0, amount + change)
    }

    func ensureClosedWindowErrorIfNeeded() {
        if !openedWhileWindowOpen {
            formError = CheckInSubmissionRules.closedWindowMessage
        }
    }

    func close(store: AppStore) {
        store.showCompletion = false
    }

    func formatElapsed(_ value: TimeInterval) -> String {
        let total = Int(value)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func previousAmount(store: AppStore, challenge: CahootsChallenge) -> Double? {
        guard let snapshot = store.snapshot else { return nil }
        return snapshot.submissions
            .filter { $0.challengeID == challenge.id && $0.userID == snapshot.currentUser.id }
            .sorted { $0.completedAt > $1.completedAt }
            .first?
            .quantity
    }
}
