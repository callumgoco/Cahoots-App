import Foundation
@preconcurrency import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.round.network-monitor")
    private var observationTask: Task<Void, Never>?

    init() {
        if ProcessInfo.processInfo.arguments.contains("-forceOffline") {
            isConnected = false
            return
        }
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
        monitor.start(queue: queue)
        observationTask = Task { [weak self] in
            for await connected in stream { self?.isConnected = connected }
        }
    }

    deinit {
        monitor.cancel()
    }
}
