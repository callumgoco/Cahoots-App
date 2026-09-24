import AVFoundation
import OSLog
import SwiftUI
import UIKit

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession?
    var position: AVCaptureDevice.Position = .front

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.position = position
        PreviewDebug.logIncoming(source: "makeUIView", view: view, session: session, position: position)
        CaptureTiming.logSinceRecord("preview makeUIView")
        CaptureTiming.logSinceWarmUp("preview makeUIView")
        view.receive(session: session, source: "makeUIView")
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.position = position
        PreviewDebug.logIncoming(source: "updateUIView", view: uiView, session: session, position: position)
        uiView.receive(session: session, source: "updateUIView")
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var position: AVCaptureDevice.Position = .front

        /// Last real capture session. A later SwiftUI update can pass nil and must not clear this.
        private var heldSession: AVCaptureSession?
        private var didLogReadyLayout = false
        private var didLogMissingConnection = false

        /// Portrait sensor angle. The app is portrait-locked.
        private static let portraitAngle: CGFloat = 90

        func receive(session: AVCaptureSession?, source: String) {
            if let session {
                if heldSession !== session {
                    AppLog.capture.info("Preview \(source, privacy: .public) stored session \(PreviewDebug.id(session), privacy: .public) running=\(session.isRunning, privacy: .public) view=\(PreviewDebug.id(self), privacy: .public)")
                }
                heldSession = session
            } else if heldSession != nil {
                AppLog.capture.info("Preview \(source, privacy: .public) ignored nil session. Keeping \(PreviewDebug.id(self.heldSession), privacy: .public) view=\(PreviewDebug.id(self), privacy: .public) bounds=\(PreviewDebug.size(self.bounds), privacy: .public) inWindow=\(self.window != nil, privacy: .public)")
            } else {
                AppLog.capture.info("Preview \(source, privacy: .public) has no session yet. view=\(PreviewDebug.id(self), privacy: .public) bounds=\(PreviewDebug.size(self.bounds), privacy: .public) inWindow=\(self.window != nil, privacy: .public)")
            }
            applyHeldSession(source: source)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyHeldSession(source: "layout")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            AppLog.capture.info("Preview moved. inWindow=\(self.window != nil, privacy: .public) bounds=\(PreviewDebug.size(self.bounds), privacy: .public) held=\(PreviewDebug.id(self.heldSession), privacy: .public) installed=\(PreviewDebug.id(self.previewLayer.session), privacy: .public) view=\(PreviewDebug.id(self), privacy: .public)")
            if self.window != nil {
                CaptureTiming.logSinceRecord("preview entered window")
            }
            applyHeldSession(source: "didMoveToWindow")
        }

        private var hasDrawableSize: Bool {
            bounds.width > 1 && bounds.height > 1
        }

        private func applyHeldSession(source: String) {
            previewLayer.videoGravity = .resizeAspectFill
            guard let heldSession else { return }

            let ready = window != nil && hasDrawableSize
            guard ready else { return }
            if previewLayer.session !== heldSession {
                let started = ProcessInfo.processInfo.systemUptime
                previewLayer.session = heldSession
                let elapsed = Int(((ProcessInfo.processInfo.systemUptime - started) * 1000).rounded())
                AppLog.capture.info("Preview installed session \(PreviewDebug.id(heldSession), privacy: .public) from \(source, privacy: .public). running=\(heldSession.isRunning, privacy: .public) attachMs=\(elapsed, privacy: .public) bounds=\(PreviewDebug.size(self.bounds), privacy: .public) view=\(PreviewDebug.id(self), privacy: .public)")
                CaptureTiming.logSinceWarmUp("preview session attached")
                CaptureTiming.logSinceRecord("preview session attached")
            }

            if !didLogReadyLayout {
                didLogReadyLayout = true
                AppLog.capture.info("Preview ready to draw. bounds=\(PreviewDebug.size(self.bounds), privacy: .public) connection=\(self.previewLayer.connection == nil ? "nil" : "set", privacy: .public) session=\(PreviewDebug.id(self.previewLayer.session), privacy: .public) view=\(PreviewDebug.id(self), privacy: .public)")
                CaptureTiming.logSinceRecord("preview ready to draw")
            }
            applyConnectionSettings(source: source)
        }

        private func applyConnectionSettings(source: String) {
            guard let connection = previewLayer.connection else {
                guard !didLogMissingConnection else { return }
                didLogMissingConnection = true
                AppLog.capture.info("Preview connection missing. source=\(source, privacy: .public) bounds=\(PreviewDebug.size(self.bounds), privacy: .public) inWindow=\(self.window != nil, privacy: .public) view=\(PreviewDebug.id(self), privacy: .public)")
                return
            }
            didLogMissingConnection = false
            var changed = false
            if connection.isVideoRotationAngleSupported(Self.portraitAngle),
               connection.videoRotationAngle != Self.portraitAngle {
                connection.videoRotationAngle = Self.portraitAngle
                changed = true
            }
            if connection.isVideoMirroringSupported {
                let mirrored = position == .front
                if connection.automaticallyAdjustsVideoMirroring || connection.isVideoMirrored != mirrored {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = mirrored
                    changed = true
                }
            }
            if changed {
                AppLog.capture.info("Preview connection updated from \(source, privacy: .public). angle=\(connection.videoRotationAngle, privacy: .public) mirrored=\(connection.isVideoMirrored, privacy: .public) bounds=\(PreviewDebug.size(self.bounds), privacy: .public) view=\(PreviewDebug.id(self), privacy: .public)")
            }
        }
    }
}

enum PreviewDebug {
    static func id(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }
        return String(UInt(bitPattern: ObjectIdentifier(object)))
    }

    static func size(_ bounds: CGRect) -> String {
        "\(Int(bounds.width))x\(Int(bounds.height))"
    }

    static func logIncoming(source: String, view: UIView, session: AVCaptureSession?, position: AVCaptureDevice.Position) {
        let sessionState = session == nil ? "nil" : "set"
        let running = session?.isRunning ?? false
        AppLog.capture.info("Preview \(source, privacy: .public) incoming session=\(sessionState, privacy: .public) sessionID=\(id(session), privacy: .public) running=\(running, privacy: .public) position=\(position == .front ? "front" : "back", privacy: .public) view=\(id(view), privacy: .public) bounds=\(size(view.bounds), privacy: .public) inWindow=\(view.window != nil, privacy: .public)")
    }
}
