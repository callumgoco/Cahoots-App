import AVKit
import SwiftUI

struct PeerClipPlayButton: View {
    let clip: WorkoutClip
    var showsLabel: Bool = false

    var body: some View {
        PeerClipPlaybackTrigger(clip: clip) {
            HStack(spacing: 4) {
                Image(systemName: "play.circle.fill")
                    .font(showsLabel ? .title2 : .title3)
                if showsLabel {
                    Text("Play")
                        .font(.caption.weight(.semibold))
                }
            }
            .frame(minWidth: showsLabel ? 64 : 28, minHeight: showsLabel ? 36 : 28)
        }
    }

    static func playableClip(from submission: Submission) -> WorkoutClip? {
        PeerClipPlayback.playableClip(from: submission)
    }
}

/// Shared resolve helpers for peer clip playback.
enum PeerClipPlayback {
    static func playableClip(from submission: Submission) -> WorkoutClip? {
        if let finish = submission.clips.last(where: { $0.kind == .finish && ($0.remotePath != nil || $0.localFilename != nil) }) {
            return finish
        }
        return submission.clips.last { $0.remotePath != nil || $0.localFilename != nil }
    }

    static func resolveURL(for clip: WorkoutClip, repository: any AppRepository) async throws -> URL {
        if let local = clip.localFilename, WorkoutClipStore.fileExists(local) {
            return WorkoutClipStore.fileURL(for: local)
        }

        let cached = WorkoutClipStore.cachedFileURL(forClipID: clip.id)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let ticket = try await repository.requestClipDownloadURL(clipID: clip.id)
        if ticket.downloadURL.isFileURL {
            return ticket.downloadURL
        }

        let (data, _) = try await URLSession.shared.data(from: ticket.downloadURL)
        try data.write(to: cached, options: .atomic)
        return cached
    }
}

struct PeerClipPlaybackTrigger<Label: View>: View {
    let clip: WorkoutClip
    var accessibilityPlayLabel: String = String(localized: "Play clip")
    @ViewBuilder var label: () -> Label

    @Environment(AppStore.self) private var store
    @State private var isLoading = false
    @State private var playbackURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task { await openClip() }
        } label: {
            ZStack {
                label()
                    .opacity(isLoading ? 0.35 : 1)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(accessibilityPlayLabel)
        .peerClipPlaybackOverlays(playbackURL: $playbackURL, errorMessage: $errorMessage)
    }

    @MainActor
    private func openClip() async {
        isLoading = true
        defer { isLoading = false }
        do {
            playbackURL = try await PeerClipPlayback.resolveURL(
                for: clip,
                repository: store.environment.repository
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Plays a clip when `clip` becomes non-nil (e.g. from the crew status rail).
struct PeerClipPlaybackPresenter: View {
    @Binding var clip: WorkoutClip?

    @Environment(AppStore.self) private var store
    @State private var playbackURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: clip?.id) {
                guard let clip else { return }
                do {
                    playbackURL = try await PeerClipPlayback.resolveURL(
                        for: clip,
                        repository: store.environment.repository
                    )
                } catch {
                    errorMessage = error.localizedDescription
                    self.clip = nil
                }
            }
            .peerClipPlaybackOverlays(
                playbackURL: $playbackURL,
                errorMessage: $errorMessage,
                onDismissPlayback: { clip = nil }
            )
    }
}

private extension View {
    func peerClipPlaybackOverlays(
        playbackURL: Binding<URL?>,
        errorMessage: Binding<String?>,
        onDismissPlayback: (() -> Void)? = nil
    ) -> some View {
        self
            .sheet(isPresented: Binding(
                get: { playbackURL.wrappedValue != nil },
                set: { if !$0 {
                    playbackURL.wrappedValue = nil
                    onDismissPlayback?()
                } }
            )) {
                if let url = playbackURL.wrappedValue {
                    VideoPlayerRepresentable(url: url)
                        .ignoresSafeArea()
                }
            }
            .alert(
                "Clip unavailable",
                isPresented: Binding(
                    get: { errorMessage.wrappedValue != nil },
                    set: { if !$0 { errorMessage.wrappedValue = nil } }
                ),
                actions: { Button("OK", role: .cancel) { errorMessage.wrappedValue = nil } },
                message: { Text(errorMessage.wrappedValue ?? "") }
            )
    }
}

struct VideoPlayerRepresentable: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
