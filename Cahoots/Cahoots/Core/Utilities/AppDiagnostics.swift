import Foundation
import MetricKit
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Cahoots"
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let routing = Logger(subsystem: subsystem, category: "routing")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let capture = Logger(subsystem: subsystem, category: "capture")
}

/// Monotonic timestamps for the record → preview path. Logged as milliseconds since the mark.
enum CaptureTiming {
    private static var recordTappedAt: TimeInterval?
    private static var warmUpStartedAt: TimeInterval?

    static func markWarmUp() {
        warmUpStartedAt = ProcessInfo.processInfo.systemUptime
        AppLog.capture.info("Timing warm-up started +0ms")
    }

    static func markRecordTapped() {
        recordTappedAt = ProcessInfo.processInfo.systemUptime
        AppLog.capture.info("Timing record tapped +0ms")
    }

    static func logSinceRecord(_ event: String) {
        guard let recordTappedAt else { return }
        let elapsed = (ProcessInfo.processInfo.systemUptime - recordTappedAt) * 1000
        AppLog.capture.info("Timing \(event, privacy: .public) +\(Int(elapsed.rounded()), privacy: .public)ms since record tap")
    }

    static func logSinceWarmUp(_ event: String) {
        guard let warmUpStartedAt else { return }
        let elapsed = (ProcessInfo.processInfo.systemUptime - warmUpStartedAt) * 1000
        AppLog.capture.info("Timing \(event, privacy: .public) +\(Int(elapsed.rounded()), privacy: .public)ms since warm-up")
    }
}

final class CahootsMetricSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CahootsMetricSubscriber()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        AppLog.lifecycle.info("Received \(payloads.count, privacy: .public) MetricKit payloads")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        AppLog.lifecycle.error("Received \(payloads.count, privacy: .public) MetricKit diagnostic payloads")
    }
}
