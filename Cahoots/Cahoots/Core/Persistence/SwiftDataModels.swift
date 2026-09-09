import Foundation
import SwiftData

@Model
final class AppSnapshotEntity {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date

    init(key: String = "primary", payload: Data, updatedAt: Date = .now) {
        self.key = key
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class CachedUserEntity {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var timezoneIdentifier: String
    var updatedAt: Date

    init(id: UUID, displayName: String, timezoneIdentifier: String, updatedAt: Date) {
        self.id = id
        self.displayName = displayName
        self.timezoneIdentifier = timezoneIdentifier
        self.updatedAt = updatedAt
    }
}

@Model
final class CachedGroupEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var ownerID: UUID
    var updatedAt: Date

    init(id: UUID, name: String, emoji: String, ownerID: UUID, updatedAt: Date) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.ownerID = ownerID
        self.updatedAt = updatedAt
    }
}

@Model
final class CachedChallengeEntity {
    @Attribute(.unique) var id: UUID
    var groupID: UUID
    var title: String
    var status: String
    var payload: Data
    var updatedAt: Date

    init(id: UUID, groupID: UUID, title: String, status: String, payload: Data, updatedAt: Date) {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.status = status
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class CachedSubmissionEntity {
    @Attribute(.unique) var clientGeneratedID: UUID
    var submissionID: UUID
    var challengeID: UUID
    var userID: UUID
    var quantity: Double
    var completedAt: Date
    var syncState: String
    var payload: Data

    init(submission: Submission, payload: Data) {
        clientGeneratedID = submission.clientGeneratedID
        submissionID = submission.id
        challengeID = submission.challengeID
        userID = submission.userID
        quantity = submission.quantity
        completedAt = submission.completedAt
        syncState = submission.syncState.rawValue
        self.payload = payload
    }
}

@Model
final class CachedScoreEventEntity {
    @Attribute(.unique) var id: UUID
    var challengeID: UUID
    var userID: UUID
    var points: Int
    var createdAt: Date

    init(event: ScoreEvent) {
        id = event.id
        challengeID = event.challengeID
        userID = event.userID
        points = event.points
        createdAt = event.createdAt
    }
}

