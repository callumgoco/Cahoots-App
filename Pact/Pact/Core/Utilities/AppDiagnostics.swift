import Foundation
import MetricKit
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Round"
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let routing = Logger(subsystem: subsystem, category: "routing")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}

final class RoundMetricSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = RoundMetricSubscriber()
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
