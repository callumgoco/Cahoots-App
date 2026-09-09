import AVKit
import SwiftUI

struct PeerClipPlayButton: View {
    let clip: WorkoutClip

    @Environment(AppStore.self) private var store
    @State private var isLoading = false
    @State private var playbackURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task { await openClip() }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel("Play clip")
        .sheet(isPresented: Binding(
            get: { playbackURL != nil },
            set: { if !$0 { playbackURL = nil } }
        )) {
            if let playbackURL {
                VideoPlayerRepresentable(url: playbackURL)
                    .ignoresSafeArea()
            }
        }
        .alert(
            "Clip unavailable",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { errorMessage = nil } },
            message: { Text(errorMessage ?? "") }
        )
    }

    @MainActor
    private func openClip() async {
        isLoading = true
        defer { isLoading = false }
        do {
            playbackURL = try await Self.resolvePlaybackURL(
                for: clip,
                repository: store.environment.repository
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func resolvePlaybackURL(for clip: WorkoutClip, repository: any AppRepository) async throws -> URL {
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

    static func playableClip(from submission: Submission) -> WorkoutClip? {
        if let finish = submission.clips.last(where: { $0.kind == .finish && ($0.remotePath != nil || $0.localFilename != nil) }) {
            return finish
        }
        return submission.clips.last { $0.remotePath != nil || $0.localFilename != nil }
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
