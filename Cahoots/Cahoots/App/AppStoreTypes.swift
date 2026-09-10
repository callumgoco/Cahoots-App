import Foundation

enum LoadState: Equatable {
    case idle, loading, loaded, empty, error(String)
}

enum CheckInLogResult: Equatable, Sendable {
    case saved(points: Int, syncState: SyncState)
    case validationFailed(message: String)
    case persistenceFailed(message: String)
}

enum NotificationAuthorizationState: Equatable, Sendable {
    case undetermined, denied, authorized, provisional
}
