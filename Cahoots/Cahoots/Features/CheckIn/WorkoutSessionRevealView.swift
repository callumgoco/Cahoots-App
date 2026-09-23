import SwiftUI

struct WorkoutSessionRevealView: View {
    @Bindable var controller: WorkoutSessionController
    let store: AppStore
    let onDone: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var pointsSize: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var accessibilityPointsSize: CGFloat = 56

    var body: some View {
        ZStack {
            backdrop
            ScrollView {
                VStack(spacing: AppSpacing.large) {
                    CahootsCard(elevated: true) {
                        VStack(spacing: AppSpacing.extraLarge) {
                            if let points = controller.submittedPoints {
                                Text(points > 0 ? "+\(points)" : "Saved")
                                    .font(
                                        .system(
                                            size: dynamicTypeSize.isAccessibilitySize ? accessibilityPointsSize : pointsSize,
                                            weight: .heavy,
                                            design: .rounded
                                        )
                                    )
                                    .monospacedDigit()
                                    .foregroundStyle(points > 0 ? AppColors.accent : AppColors.ink)
                                Text(points > 0 ? "points today" : "Progress ready for another check-in")
                                    .font(.title3.bold())
                                if let submittedSyncState = controller.submittedSyncState {
                                    StatusPill(
                                        text: FriendFacingCopy.syncLabel(for: submittedSyncState),
                                        kind: submittedSyncState == .synced ? .positive : .warning
                                    )
                                }
                            }
                            if let previewURL = controller.previewURL, FileManager.default.fileExists(atPath: previewURL.path) {
                                VideoPlayerRepresentable(url: previewURL)
                                    .frame(height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                            } else if controller.submittedPoints != nil {
                                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                                    .fill(AppColors.chip)
                                    .frame(height: 120)
                                    .overlay {
                                        Text("Preview unavailable")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppColors.secondaryInk)
                                    }
                                    .accessibilityLabel("Preview unavailable")
                            }
                            WorkoutSessionCrewStrip(
                                store: store,
                                challenge: store.currentChallenge,
                                spoilered: false
                            )
                            if let stillNeed = CrewAccountabilityCopy.stillNeedToCheckIn(entries: store.todayMemberStatuses) {
                                Text(stillNeed)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppColors.secondaryInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("checkIn.stillNeed")
                            }
                            Button("Done", action: onDone)
                                .buttonStyle(PrimaryButtonStyle())
                                .accessibilityIdentifier("checkIn.done")
                        }
                    }
                }
                .padding(AppSpacing.page)
                .padding(.vertical, AppSpacing.large)
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            AppColors.page.ignoresSafeArea()
            if let previewURL = controller.previewURL, FileManager.default.fileExists(atPath: previewURL.path) {
                VideoPlayerRepresentable(url: previewURL)
                    .ignoresSafeArea()
                    .blur(radius: 28)
                    .opacity(0.45)
                    .allowsHitTesting(false)
            }
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

struct WorkoutSessionCrewStrip: View {
    let store: AppStore
    let challenge: CahootsChallenge?
    let spoilered: Bool

    var body: some View {
        let peers = store.todayPeerCheckIns
        VStack(alignment: .leading, spacing: AppSpacing.small) {
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
                        } else {
                            if let clip = PeerClipPlayButton.playableClip(from: submission) {
                                PeerClipPlayButton(clip: clip)
                            }
                            if let challenge {
                                Text("\(submission.quantity.formatted()) \(challenge.measurementType.shortName)")
                                    .font(.subheadline.bold().monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.medium)
        .environment(\.colorScheme, .dark)
        .background(AppColors.raised, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .foregroundStyle(AppColors.ink)
        .accessibilityIdentifier("workoutSession.crewStrip")
    }
}
