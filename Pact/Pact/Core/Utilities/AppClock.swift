import Foundation

protocol AppClock: Sendable {
    var now: Date { get }
    func sleep(until date: Date) async throws
}

struct SystemAppClock: AppClock {
    var now: Date { .now }

    func sleep(until date: Date) async throws {
        let duration = max(0, date.timeIntervalSinceNow)
        try await Task.sleep(for: .seconds(duration))
    }
}

struct FixedAppClock: AppClock {
    let now: Date

    func sleep(until date: Date) async throws {}
}

