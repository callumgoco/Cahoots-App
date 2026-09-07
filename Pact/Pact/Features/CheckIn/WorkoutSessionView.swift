import AVFoundation
import AVKit
import SwiftUI
import UIKit

private enum WorkoutSessionPhase: Equatable {
    case prep
    case countdown(Int)
    case record
    case review
    case waitingForFinish
    case confirm
    case reveal
    case permissionDenied
}

struct WorkoutSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    @State private var phase: WorkoutSessionPhase = .prep
    @State private var capture: (any WorkoutCapturing)?
    @State private var recordedClips: [WorkoutClip] = []
    @State private var currentKind: WorkoutClipKind = .set
    @State private var recordingElapsed: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var previewURL: URL?
    @State private var amount: Double = 0
    @State private var isSubmitting = false
    @State private var submittedPoints: Int?
    @State private var submittedSyncState: SyncState?
    @State private var formError: String?
    @State private var showHighConfirmation = false
    @State private var captureError: String?
    @State private var sessionRequirementDate: Date?
    @State private var openedWhileWindowOpen = false
    @FocusState private var amountIsFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .prep: prep
                case .countdown(let value): countdown(value)
                case .record: record
                case .review: review
                case .waitingForFinish: waitingForFinish
                case .confirm: confirm
                case .reveal: reveal
                case .permissionDenied: permissionDenied
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(dismissLabel) { close() }
                        .disabled(isSubmitting || (capture?.isRecording == true))
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting || capture?.isRecording == true || submittedPoints != nil)
        .onAppear { bootstrap() }
        .onDisappear {
            recordingTimer?.invalidate()
            capture?.tearDown()
        }
        .confirmationDialog("That’s much higher than the target", isPresented: $showHighConfirmation, titleVisibility: .visible) {
            Button("Submit anyway") { Task { await submit() } }
            Button("Review amount", role: .cancel) {}
        } message: {
            Text("Check that the quantity and unit are correct. Bonus points remain capped at 10.")
        }
        .sensoryFeedback(.success, trigger: submittedPoints)
    }

    private var navigationTitle: String {
        switch phase {
        case .reveal: String(localized: "Crew reveal")
        case .confirm: String(localized: "Confirm amount")
        case .waitingForFinish: String(localized: "Start clip saved")
        default: String(localized: "Log workout")
        }
    }

    private var dismissLabel: String {
        phase == .waitingForFinish ? String(localized: "Finish later") : String(localized: "Close")
    }

    private var challenge: RoundChallenge? { store.currentChallenge }

    private func bootstrap() {
        guard let challenge else { return }
        amount = max(challenge.minimumQuantity, previousAmount ?? 0)
        let now = store.environment.clock.now
        if let userID = store.currentUser?.id,
           let pending = PendingWorkoutSessionStore.load(challengeID: challenge.id, userID: userID) {
            recordedClips = [pending.startClip]
            currentKind = .finish
            sessionRequirementDate = pending.requirementDate
            openedWhileWindowOpen = true
            phase = .waitingForFinish
            return
        }
        sessionRequirementDate = ScheduleEngine.requirementDay(for: now, challenge: challenge) ?? now
        openedWhileWindowOpen = CheckInSubmissionRules.isWindowOpen(challenge: challenge, at: now)
        if !openedWhileWindowOpen {
            formError = CheckInSubmissionRules.closedWindowMessage
        }
        currentKind = challenge.measurementType.requiresTwoClips ? .start : .set
        phase = .prep
        Task { await prepareCapture() }
    }

    private func prepareCapture() async {
        let controller = WorkoutCaptureController.make()
        capture = controller
        do {
            try await controller.prepare()
            captureError = nil
        } catch WorkoutCaptureError.permissionDenied {
            phase = .permissionDenied
        } catch {
            captureError = error.localizedDescription
        }
    }

    private var prep: some View {
        VStack(spacing: AppSpacing.extraLarge) {
            if let challenge {
                VStack(spacing: AppSpacing.small) {
                    Text(challenge.activityType)
                        .font(.title2.bold())
                    Text("Target · \(challenge.quantityLabel)")
                        .foregroundStyle(AppColors.secondaryInk)
                    if challenge.measurementType.requiresTwoClips {
                        Text(currentKind == .start
                             ? String(localized: "Record a short start clip for the crew, then finish after your activity. You enter the minutes — this round is honour system.")
                             : String(localized: "Record your finish clip for the crew. You enter the amount — this round is honour system."))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppColors.secondaryInk)
                    } else {
                        Text("A short clip for the crew. You enter the number — this round is honour system.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppColors.secondaryInk)
                    }
                }
                .padding(.top, AppSpacing.large)
            }
            if !store.todayPeerCheckIns.isEmpty {
                crewStrip(spoilered: !store.canRevealTodayQuantities)
            }
            if let captureError {
                Label(captureError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.danger)
                    .font(.footnote.weight(.semibold))
            }
            Spacer()
            if !openedWhileWindowOpen, let formError {
                Label(formError, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(AppColors.danger)
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            Button("Start") { beginCountdown() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!openedWhileWindowOpen)
                .accessibilityIdentifier("workoutSession.start")
            Button("Skip countdown") { beginRecording() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.secondaryInk)
                .disabled(!openedWhileWindowOpen)
                .accessibilityIdentifier("workoutSession.skipCountdown")
        }
        .padding(AppSpacing.page)
        .roundPage()
    }

    private func countdown(_ value: Int) -> some View {
        ZStack {
            AppColors.ink.ignoresSafeArea()
            Text(value == 0 ? "START" : "\(value)")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 72 : 120, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .accessibilityIdentifier("workoutSession.countdown")
        }
        .onAppear {
            if reduceMotion {
                beginRecording()
                return
            }
            Task {
                for next in stride(from: value, through: 1, by: -1) {
                    phase = .countdown(next)
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
                phase = .countdown(0)
                try? await Task.sleep(nanoseconds: 350_000_000)
                beginRecording()
            }
        }
    }

    private var record: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewRepresentable(layer: capture?.previewLayer)
                .ignoresSafeArea()
            if capture?.isUsingStub == true {
                Color.black.opacity(0.85).ignoresSafeArea()
                Text("Camera preview (stub)")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
            VStack {
                HStack {
                    Label(formatElapsed(recordingElapsed), systemImage: "record.circle.fill")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.red)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Button {
                        Task { try? await capture?.flipCamera() }
                    } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(.title3.bold())
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Flip camera")
                    .accessibilityIdentifier("workoutSession.flip")
                }
                .padding(AppSpacing.page)
                Spacer()
                Text(recordHint)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)
                Button {
                    Task { await stopRecording() }
                } label: {
                    Circle()
                        .fill(.red)
                        .frame(width: 72, height: 72)
                        .overlay(RoundedRectangle(cornerRadius: 8).fill(.white).frame(width: 28, height: 28))
                }
                .accessibilityLabel("Stop recording")
                .accessibilityIdentifier("workoutSession.stop")
                .padding(.bottom, 40)
            }
        }
        .onAppear { Task { await startRecording() } }
    }

    private var recordHint: String {
        switch currentKind {
        case .set: String(localized: "Film your set")
        case .start: String(localized: "Start clip")
        case .finish: String(localized: "Finish clip")
        }
    }

    private var review: some View {
        VStack(spacing: AppSpacing.large) {
            if let previewURL, FileManager.default.fileExists(atPath: previewURL.path) {
                VideoPlayerRepresentable(url: previewURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(AppColors.card)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .overlay {
                        VStack(spacing: AppSpacing.small) {
                            Image(systemName: "video.slash")
                                .font(.largeTitle)
                                .foregroundStyle(AppColors.secondaryInk)
                            Text("Preview unavailable")
                                .font(.headline)
                            Text("Your clip is saved. You can still use it for this check-in.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.secondaryInk)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppSpacing.large)
                        }
                    }
                    .accessibilityLabel("Preview unavailable")
            }
            Text(clipDurationLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.secondaryInk)
            if let formError {
                Label(formError, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(AppColors.danger)
            }
            Spacer()
            Button("Use this clip") { acceptCurrentClip() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!(recordedClips.last.map { $0.durationSeconds >= WorkoutClipRules.minimumDuration } ?? false))
                .accessibilityIdentifier("workoutSession.useClip")
            Button("Retake") { retake() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("workoutSession.retake")
        }
        .padding(AppSpacing.page)
        .roundPage()
    }

    private var waitingForFinish: some View {
        VStack(spacing: AppSpacing.extraLarge) {
            Image(systemName: "figure.walk")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(AppColors.accent)
            Text("Start clip saved")
                .font(.title2.bold())
            Text("Come back after your activity to record the finish clip and confirm today’s amount.")
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.secondaryInk)
            Spacer()
            Button("Record finish clip") {
                currentKind = .finish
                phase = .prep
                Task { await prepareCapture() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("workoutSession.recordFinish")
            Button("Discard start clip", role: .destructive) {
                if let challenge, let userID = store.currentUser?.id {
                    PendingWorkoutSessionStore.clear(challengeID: challenge.id, userID: userID)
                    store.notePendingWorkoutSessionChanged()
                }
                recordedClips = []
                currentKind = challenge?.measurementType.requiresTwoClips == true ? .start : .set
                phase = .prep
            }
        }
        .padding(AppSpacing.page)
        .roundPage()
    }

    private var confirm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppSpacing.extraLarge) {
                    if let challenge {
                        VStack(spacing: AppSpacing.micro) {
                            Text("Today’s amount")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.secondaryInk)
                            TextField("0", value: $amount, format: .number.precision(.fractionLength(0...1)))
                                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 56 : 88, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                                .keyboardType(challenge.measurementType == .distance ? .decimalPad : .numberPad)
                                .focused($amountIsFocused)
                                .accessibilityLabel("Completed quantity in \(challenge.measurementType.displayName)")
                                .accessibilityIdentifier("checkIn.amount")
                            Text(challenge.measurementType.displayName)
                                .font(.title2.bold())
                                .foregroundStyle(AppColors.secondaryInk)
                        }
                        .padding(.top, AppSpacing.large)

                        HStack(spacing: AppSpacing.small) {
                            incrementButton("−1", change: -1)
                            incrementButton("+1", change: 1)
                            incrementButton("+5", change: 5)
                        }

                        if amount >= challenge.minimumQuantity {
                            Text("+\(ScoringEngine.points(completedQuantity: amount, minimumQuantity: challenge.minimumQuantity)) points if you finish")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                    if let formError {
                        Label(formError, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(AppColors.danger)
                            .font(.body.weight(.semibold))
                    }
                    Label("A short clip for the crew. You enter the number — this round is honour system.", systemImage: "hand.raised.fill")
                        .font(.footnote)
                        .foregroundStyle(AppColors.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(AppSpacing.page)
            }
            .interactiveKeyboardDismiss()
            Button(amount >= (challenge?.minimumQuantity ?? 0) ? "Complete check-in" : "Save progress") {
                if let challenge, amount >= challenge.minimumQuantity * 5 { showHighConfirmation = true }
                else { Task { await submit() } }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(
                amount <= 0
                    || isSubmitting
                    || !openedWhileWindowOpen
                    || !WorkoutClipRules.areValid(recordedClips, for: challenge?.measurementType ?? .repetitions)
            )
            .accessibilityIdentifier("checkIn.submit")
            .padding(AppSpacing.page)
            .background(.bar)
        }
        .roundPage()
        .keyboardDoneToolbar()
        .onAppear {
            if !openedWhileWindowOpen {
                formError = CheckInSubmissionRules.closedWindowMessage
            }
        }
    }

    private var reveal: some View {
        ScrollView {
            VStack(spacing: AppSpacing.extraLarge) {
                if let points = submittedPoints {
                    Text(points > 0 ? "+\(points)" : "Saved")
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 56 : 72, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(points > 0 ? AppColors.accent : AppColors.ink)
                    Text(points > 0 ? "points today" : "Progress ready for another check-in")
                        .font(.title3.bold())
                    if let submittedSyncState {
                        StatusPill(
                            text: FriendFacingCopy.syncLabel(for: submittedSyncState),
                            kind: submittedSyncState == .synced ? .positive : .warning
                        )
                    }
                }
                if let previewURL, FileManager.default.fileExists(atPath: previewURL.path) {
                    VideoPlayerRepresentable(url: previewURL)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                } else if submittedPoints != nil {
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .fill(AppColors.card)
                        .frame(height: 120)
                        .overlay {
                            Text("Preview unavailable")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.secondaryInk)
                        }
                }
                crewStrip(spoilered: false)
                Button("Done") {
                    store.showCompletion = false
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("checkIn.done")
            }
            .padding(AppSpacing.page)
        }
        .roundPage()
    }

    private var permissionDenied: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(AppColors.danger)
            Text("Camera required")
                .font(.title2.bold())
            Text("A short proof clip is required to unlock the crew feed. Honour-system-only check-ins are not available.")
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.secondaryInk)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("workoutSession.openSettings")
            Spacer()
        }
        .padding(AppSpacing.page)
        .roundPage()
    }

    private func crewStrip(spoilered: Bool) -> some View {
        let peers = store.todayPeerCheckIns
        return VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(spoilered ? "Crew posted · hidden until you go" : "Crew today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.secondaryInk)
            if peers.isEmpty {
                Text("You’re first today.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.secondaryInk)
            } else {
                ForEach(peers) { submission in
                    HStack(spacing: AppSpacing.small) {
                        if let user = store.snapshot?.users.first(where: { $0.id == submission.userID }) {
                            AvatarView(user: user, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName).font(.subheadline.bold())
                                Text(submission.submittedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.secondaryInk)
                            }
                        }
                        Spacer()
                        if spoilered {
                            Text("Hidden")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppColors.card, in: Capsule())
                        } else if let challenge {
                            Text("\(submission.quantity.formatted()) \(challenge.measurementType.shortName)")
                                .font(.subheadline.bold().monospacedDigit())
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.medium)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .accessibilityIdentifier("workoutSession.crewStrip")
    }

    private func incrementButton(_ title: String, change: Double) -> some View {
        Button(title) { amount = max(0, amount + change) }
            .font(.title2.bold().monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .foregroundStyle(AppColors.ink)
    }

    private var previousAmount: Double? {
        guard let snapshot = store.snapshot, let challenge else { return nil }
        return snapshot.submissions
            .filter { $0.challengeID == challenge.id && $0.userID == snapshot.currentUser.id }
            .sorted { $0.completedAt > $1.completedAt }
            .first?
            .quantity
    }

    private var clipDurationLabel: String {
        guard let last = recordedClips.last else { return "" }
        return String(localized: "\(Int(last.durationSeconds.rounded())) seconds")
    }

    private func beginCountdown() {
        if reduceMotion {
            beginRecording()
        } else {
            phase = .countdown(3)
        }
    }

    private func beginRecording() {
        formError = nil
        phase = .record
    }

    private func startRecording() async {
        guard let capture else { return }
        let filename = WorkoutClipStore.makeFilename(kind: currentKind)
        let url = WorkoutClipStore.fileURL(for: filename)
        do {
            try await capture.startRecording(to: url)
            previewURL = url
            recordingElapsed = 0
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                Task { @MainActor in
                    recordingElapsed += 0.25
                    if recordingElapsed >= WorkoutClipRules.maximumDuration {
                        await stopRecording()
                    }
                }
            }
        } catch {
            formError = error.localizedDescription
            phase = .prep
        }
    }

    private func stopRecording() async {
        recordingTimer?.invalidate()
        recordingTimer = nil
        guard let capture else { return }
        do {
            let duration = try await capture.stopRecording()
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
            formError = error.localizedDescription
            phase = .prep
        }
    }

    private func acceptCurrentClip() {
        guard let challenge, let last = recordedClips.last, last.durationSeconds >= WorkoutClipRules.minimumDuration else {
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

    private func retake() {
        if let filename = recordedClips.first(where: { $0.kind == currentKind })?.localFilename {
            try? FileManager.default.removeItem(at: WorkoutClipStore.fileURL(for: filename))
        }
        recordedClips.removeAll { $0.kind == currentKind }
        previewURL = nil
        formError = nil
        phase = .record
    }

    private func submit() async {
        guard challenge != nil else { return }
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

    private func close() {
        store.showCompletion = false
        dismiss()
    }

    private func formatElapsed(_ value: TimeInterval) -> String {
        let total = Int(value)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct CameraPreviewRepresentable: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        if let layer {
            view.previewLayer.session = layer.session
            view.previewLayer.videoGravity = .resizeAspectFill
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let layer {
            uiView.previewLayer.session = layer.session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

private struct VideoPlayerRepresentable: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
