import Foundation

enum WorkoutSessionPhase: Equatable {
    case choose
    case prep
    case countdown(Int)
    case record
    case review
    case waitingForFinish
    case confirm
    case reveal
    case permissionDenied
}
