import Foundation
import Testing
@testable import Cahoots

struct CheckInVisibilityTests {
    @Test func revealMatrix() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = now.addingTimeInterval(3_600)
        #expect(!CheckInVisibility.canRevealToday(viewerHasCompleted: false, usedRecovery: false, now: now, deadline: deadline))
        #expect(CheckInVisibility.canRevealToday(viewerHasCompleted: true, usedRecovery: false, now: now, deadline: deadline))
        #expect(CheckInVisibility.canRevealToday(viewerHasCompleted: false, usedRecovery: true, now: now, deadline: deadline))
        #expect(CheckInVisibility.canRevealToday(viewerHasCompleted: false, usedRecovery: false, now: deadline, deadline: deadline))
        #expect(CheckInVisibility.canRevealToday(viewerHasCompleted: false, usedRecovery: false, now: deadline.addingTimeInterval(1), deadline: deadline))
    }

    @Test func redactionHidesQuantityAndMedia() {
        let clip = WorkoutClip(id: UUID(), kind: .set, durationSeconds: 5, localFilename: "a.mov", remotePath: "remote/a.mov", createdAt: .now)
        let submission = Submission(
            id: UUID(), clientGeneratedID: UUID(), challengeID: UUID(), userID: UUID(),
            requirementDate: .now, quantity: 20, measurementType: .repetitions, completedAt: .now,
            submittedAt: .now, syncState: .synced, verificationState: .accepted, createdAt: .now, updatedAt: .now,
            clips: [clip]
        )
        let hidden = CheckInVisibility.redacted(submission, reveal: false)
        #expect(hidden.quantity == 0)
        #expect(hidden.clips.first?.localFilename == nil)
        #expect(hidden.clips.first?.remotePath == nil)
        let shown = CheckInVisibility.redacted(submission, reveal: true)
        #expect(shown.quantity == 20)
        #expect(shown.clips.first?.remotePath == "remote/a.mov")
    }

    @Test func clipRulesRequireSetOrStartFinish() {
        let set = WorkoutClip(id: UUID(), kind: .set, durationSeconds: 3, localFilename: "set.mov", remotePath: nil, createdAt: .now)
        #expect(WorkoutClipRules.areValid([set], for: .repetitions))
        #expect(!WorkoutClipRules.areValid([set], for: .minutes))
        let start = WorkoutClip(id: UUID(), kind: .start, durationSeconds: 3, localFilename: "start.mov", remotePath: nil, createdAt: .now)
        let finish = WorkoutClip(id: UUID(), kind: .finish, durationSeconds: 4, localFilename: "finish.mov", remotePath: nil, createdAt: .now)
        #expect(WorkoutClipRules.areValid([start, finish], for: .minutes))
        #expect(!WorkoutClipRules.areValid([start], for: .distance))
        let short = WorkoutClip(id: UUID(), kind: .set, durationSeconds: 1, localFilename: "short.mov", remotePath: nil, createdAt: .now)
        #expect(!WorkoutClipRules.areValid([short], for: .repetitions))
    }

    @Test func friendPostedCopySplitsByViewerState() {
        let incomplete = FriendPostedCopy.lockScreenBody(actorName: "Jordan", groupName: "Saturday Crew", viewerHasCompleted: false)
        let complete = FriendPostedCopy.lockScreenBody(actorName: "Jordan", groupName: "Saturday Crew", viewerHasCompleted: true)
        #expect(incomplete.contains("log yours"))
        #expect(complete.contains("just posted"))
        #expect(!incomplete.contains("15"))
        #expect(!complete.contains("points"))
    }

    @Test func demoSeedIncludesPeerPostsAndMigratesToV3() {
        let snapshot = DemoSeed.make()
        #expect(snapshot.schemaVersion == 3)
        #expect(snapshot.submissions.contains { $0.userID != snapshot.currentUser.id && !$0.clips.isEmpty })
        var legacy = snapshot
        legacy.schemaVersion = 2
        #expect(SnapshotMigrator.migrate(legacy).schemaVersion == 3)
    }
}

struct CheckInSubmissionRulesTests {
    @Test func pinnedSessionSurvivesPastDeadline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let openAt = calendar.date(byAdding: .minute, value: 11 * 60 + 58, to: day)!
        let afterDeadline = calendar.date(byAdding: .minute, value: 12 * 60 + 1, to: day)!
        let challenge = CahootsChallenge(
            id: UUID(), groupID: UUID(), proposalID: nil, title: "Test", activityType: "push-ups",
            measurementType: .repetitions, minimumQuantity: 15, frequencyType: .daily,
            scheduledWeekdays: Set(1...7), timesPerWeek: nil, startDate: day,
            endDate: day.addingTimeInterval(10 * 86_400), challengeTimezone: "Europe/London",
            dailyDeadlineMinutes: 12 * 60, recoveryDayAllowance: 2, status: .active,
            scoringVersion: 1, createdAt: day
        )
        #expect(CheckInSubmissionRules.isWindowOpen(challenge: challenge, at: openAt))
        #expect(!CheckInSubmissionRules.isWindowOpen(challenge: challenge, at: afterDeadline))
        #expect(
            CheckInSubmissionRules.validationMessage(
                challenge: challenge,
                now: afterDeadline,
                pinnedRequirementDate: day,
                openedWhileWindowOpen: true
            ) == nil
        )
        let credited = CheckInSubmissionRules.requirementDate(
            challenge: challenge,
            now: afterDeadline,
            pinnedRequirementDate: day
        )
        #expect(calendar.isDate(credited, inSameDayAs: day))
        #expect(
            CheckInSubmissionRules.validationMessage(
                challenge: challenge,
                now: afterDeadline,
                pinnedRequirementDate: day,
                openedWhileWindowOpen: false
            ) == CheckInSubmissionRules.closedWindowMessage
        )
    }

    @Test func openingAfterDeadlineIsBlocked() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let afterDeadline = calendar.date(byAdding: .minute, value: 12 * 60 + 1, to: day)!
        let challenge = CahootsChallenge(
            id: UUID(), groupID: UUID(), proposalID: nil, title: "Test", activityType: "push-ups",
            measurementType: .repetitions, minimumQuantity: 15, frequencyType: .daily,
            scheduledWeekdays: Set(1...7), timesPerWeek: nil, startDate: day,
            endDate: day.addingTimeInterval(10 * 86_400), challengeTimezone: "Europe/London",
            dailyDeadlineMinutes: 12 * 60, recoveryDayAllowance: 2, status: .active,
            scoringVersion: 1, createdAt: day
        )
        #expect(
            CheckInSubmissionRules.validationMessage(
                challenge: challenge,
                now: afterDeadline,
                pinnedRequirementDate: nil,
                openedWhileWindowOpen: false
            ) == CheckInSubmissionRules.closedWindowMessage
        )
    }
}

struct ScheduleEngineRequirementDateTests {
    private func challenge(timezone: String, day: Date) -> CahootsChallenge {
        CahootsChallenge(
            id: UUID(), groupID: UUID(), proposalID: nil, title: "Test", activityType: "push-ups",
            measurementType: .repetitions, minimumQuantity: 15, frequencyType: .daily,
            scheduledWeekdays: Set(1...7), timesPerWeek: nil, startDate: day,
            endDate: day.addingTimeInterval(10 * 86_400), challengeTimezone: timezone,
            dailyDeadlineMinutes: 12 * 60, recoveryDayAllowance: 2, status: .active,
            scoringVersion: 1, createdAt: day
        )
    }

    private func utcMidnight(year: Int, month: Int, day: Int) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func legacyUTCMidnightMatchesTodayInLosAngeles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let challenge = challenge(timezone: "America/Los_Angeles", day: day)
        let legacyUTCMidnight = utcMidnight(year: 2026, month: 9, day: 10)
        let afternoonLocal = calendar.date(byAdding: .hour, value: 15, to: day)!
        #expect(ScheduleEngine.isSameRequirementDay(legacyUTCMidnight, afternoonLocal, challenge: challenge))
        #expect(ScheduleEngine.requirementDateToken(for: legacyUTCMidnight, challenge: challenge) == "2026-09-10")
    }

    @Test func legacyUTCMidnightDoesNotMatchPreviousEveningInLosAngeles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let challenge = challenge(timezone: "America/Los_Angeles", day: day)
        let legacyUTCMidnight = utcMidnight(year: 2026, month: 9, day: 10)
        let previousEvening = calendar.date(byAdding: .hour, value: -2, to: day)! // Sept 9 10pm
        #expect(!ScheduleEngine.isSameRequirementDay(legacyUTCMidnight, previousEvening, challenge: challenge))
    }

    @Test func challengeLocalMidnightMatchesTodayInTokyo() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let challenge = challenge(timezone: "Asia/Tokyo", day: day)
        let localMidnight = calendar.startOfDay(for: day)
        let afternoonLocal = calendar.date(byAdding: .hour, value: 14, to: day)!
        #expect(ScheduleEngine.isSameRequirementDay(localMidnight, afternoonLocal, challenge: challenge))
        #expect(ScheduleEngine.requirementDateToken(for: localMidnight, challenge: challenge) == "2026-09-10")
    }

    @Test func legacyUTCMidnightMatchesTodayInTokyo() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let challenge = challenge(timezone: "Asia/Tokyo", day: day)
        let legacyUTCMidnight = utcMidnight(year: 2026, month: 9, day: 10)
        let afternoonLocal = calendar.date(byAdding: .hour, value: 14, to: day)!
        #expect(ScheduleEngine.isSameRequirementDay(legacyUTCMidnight, afternoonLocal, challenge: challenge))
    }
}

struct ScoringTests {
    @Test func baseScoring() { #expect(ScoringEngine.points(completedQuantity: 15, minimumQuantity: 15) == 100) }
    @Test func partialCompletion() { #expect(ScoringEngine.points(completedQuantity: 14, minimumQuantity: 15) == 0) }
    @Test func normalizedBonusExamples() {
        #expect(ScoringEngine.points(completedQuantity: 18, minimumQuantity: 15) == 103)
        #expect(ScoringEngine.points(completedQuantity: 21, minimumQuantity: 15) == 106)
    }
    @Test func bonusCap() {
        #expect(ScoringEngine.points(completedQuantity: 25, minimumQuantity: 15) == 110)
        #expect(ScoringEngine.points(completedQuantity: 1_500, minimumQuantity: 15) == 110)
    }
}

struct VotingTests {
    @Test func strictMajorityPasses() {
        #expect(VotingEngine.outcome(eligibleVoters: 5, choices: [.accept, .accept, .accept], now: .now, closesAt: .now.addingTimeInterval(100)) == .open)
        #expect(VotingEngine.outcome(eligibleVoters: 5, choices: [.accept, .accept, .accept, .reject, .reject], now: .now, closesAt: .now.addingTimeInterval(100)) == .passed)
    }
    @Test func twoPersonMinimum() {
        #expect(VotingEngine.outcome(eligibleVoters: 2, choices: [.accept], now: .now, closesAt: .now.addingTimeInterval(100)) == .open)
        #expect(VotingEngine.outcome(eligibleVoters: 2, choices: [.accept, .accept], now: .now, closesAt: .now.addingTimeInterval(100)) == .passed)
    }
    @Test func soloEligibleVotersCannotPass() {
        #expect(VotingEngine.outcome(eligibleVoters: 1, choices: [.accept], now: .now, closesAt: .now.addingTimeInterval(100)) == .failed)
        #expect(VotingEngine.outcome(eligibleVoters: 0, choices: [], now: .now, closesAt: .now.addingTimeInterval(100)) == .failed)
    }
    @Test func tieFails() {
        #expect(VotingEngine.outcome(eligibleVoters: 4, choices: [.accept, .accept, .reject, .reject], now: .now, closesAt: .now.addingTimeInterval(100)) == .failed)
    }
    @Test func voteCanChange() {
        let userID = UUID(); let proposalID = UUID(); var votes: [Vote] = []
        VotingEngine.upsert(choice: .reject, userID: userID, proposalID: proposalID, votes: &votes)
        VotingEngine.upsert(choice: .accept, userID: userID, proposalID: proposalID, votes: &votes)
        #expect(votes.count == 1)
        #expect(votes.first?.choice == .accept)
    }
    @Test func allVotesFinalizeFailureEarly() {
        #expect(VotingEngine.outcome(eligibleVoters: 3, choices: [.accept, .reject, .reject], now: .now, closesAt: .now.addingTimeInterval(10_000)) == .failed)
    }

    @Test func deadlineFinalizesWithoutFullParticipation() {
        let now = Date.now
        #expect(VotingEngine.outcome(eligibleVoters: 5, choices: [.accept, .accept, .accept], now: now, closesAt: now.addingTimeInterval(-1)) == .passed)
    }

    @Test func votingWindowCopySurfacesAbsoluteCloseAndSoloHint() {
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let ends = now.addingTimeInterval(48 * 3_600)
        let open = VotingWindowCopy.statusLine(endsAt: ends, now: now)
        #expect(open.hasPrefix("Closes "))
        #expect(open.contains("("))
        #expect(VotingWindowCopy.statusLine(endsAt: now.addingTimeInterval(-1), now: now) == "Voting closed")
        #expect(VotingWindowCopy.soloVoteDisabledHint.localizedCaseInsensitiveContains("2"))
        let footnote = VotingWindowCopy.reviewFootnote(canPutToVote: true, closesAt: ends)
        #expect(footnote.localizedCaseInsensitiveContains("48"))
        #expect(VotingWindowCopy.reviewFootnote(canPutToVote: false, closesAt: ends).localizedCaseInsensitiveContains("invite"))
        #expect(VotingWindowCopy.estimatedCloseDate(from: now) == ends)
    }
}

struct ScheduleTests {
    @Test func dailySchedule() {
        let challenge = makeChallenge(frequency: .daily, weekdays: Set(1...7))
        #expect(ScheduleEngine.isScheduled(on: challenge.startDate, challenge: challenge))
        #expect(ScheduleEngine.isScheduled(on: challenge.startDate.addingTimeInterval(2 * 86_400), challenge: challenge))
    }
    @Test func selectedWeekdaysSchedule() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3))!
        let challenge = makeChallenge(start: monday, frequency: .selectedWeekdays, weekdays: [2, 4, 6])
        #expect(ScheduleEngine.isScheduled(on: monday, challenge: challenge))
        #expect(!ScheduleEngine.isScheduled(on: monday.addingTimeInterval(86_400), challenge: challenge))
    }
    @Test func challengeTimezoneDeadline() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 12))!
        let challenge = makeChallenge(start: date, frequency: .daily, weekdays: Set(1...7), timezone: "Europe/London", deadlineMinutes: 23 * 60 + 59)
        let deadline = ScheduleEngine.deadline(for: date, challenge: challenge)
        let components = calendar.dateComponents([.hour, .minute], from: deadline!)
        #expect(components.hour == 23)
        #expect(components.minute == 59)
    }

    private func makeChallenge(start: Date = .now, frequency: FrequencyType, weekdays: Set<Int>, timezone: String = "UTC", deadlineMinutes: Int = 1_439) -> CahootsChallenge {
        let day = Calendar.current.startOfDay(for: start)
        return CahootsChallenge(id: UUID(), groupID: UUID(), proposalID: nil, title: "Test", activityType: "push-ups", measurementType: .repetitions, minimumQuantity: 15, frequencyType: frequency, scheduledWeekdays: weekdays, timesPerWeek: nil, startDate: day, endDate: day.addingTimeInterval(10 * 86_400), challengeTimezone: timezone, dailyDeadlineMinutes: deadlineMinutes, recoveryDayAllowance: 2, status: .active, scoringVersion: 1, createdAt: day)
    }
}

struct ConsistencyTests {
    @Test func recoveryContinuesStreakWithoutAddingPoint() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let dates = (0..<4).map { calendar.date(byAdding: .day, value: -$0, to: today)! }.sorted()
        let completed: Set<Date> = [dates[0], dates[1], dates[3]]
        let recovery: Set<Date> = [dates[2]]
        #expect(StreakEngine.currentStreak(scheduledDates: dates, completedDates: completed, recoveryDates: recovery, calendar: calendar) == 3)
    }
    @Test func missingRequirementBreaksStreak() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        #expect(StreakEngine.currentStreak(scheduledDates: [yesterday, today], completedDates: [yesterday], recoveryDates: [], calendar: calendar) == 0)
    }
}

struct IntegrityTests {
    @Test func offlineSubmissionClientIDIsIdempotent() {
        let clientID = UUID(); var accepted = Set<UUID>()
        #expect(accepted.insert(clientID).inserted)
        #expect(!accepted.insert(clientID).inserted)
        #expect(accepted.count == 1)
    }
    @Test func leaderboardTiebreakers() {
        let now = Date.now
        let first = entry("First", points: 500, completed: 5, longest: 4, achieved: now)
        let second = entry("Second", points: 500, completed: 5, longest: 3, achieved: now.addingTimeInterval(-100))
        #expect(LeaderboardEngine.ranked([second, first]).first?.user.displayName == "First")
    }
    @Test func inviteExpiry() {
        let invite = GroupInvite(id: UUID(), groupID: UUID(), code: "ABC234", createdBy: UUID(), expiresAt: .now.addingTimeInterval(-1), maximumUses: 10, useCount: 0, revokedAt: nil)
        #expect(InviteEngine.validation(invite: invite, memberCount: 2) == .expired)
    }
    @Test func ownerMustTransferBeforeLeaving() {
        #expect(!MembershipRules.canLeave(role: .owner, activeMemberCount: 2))
        #expect(MembershipRules.canLeave(role: .owner, activeMemberCount: 1))
        #expect(MembershipRules.canLeave(role: .admin, activeMemberCount: 10))
    }
    @Test func governancePermissionMatrix() {
        #expect(GroupPermissionRules.canRemove(actor: .owner, target: .admin))
        #expect(GroupPermissionRules.canRemove(actor: .admin, target: .member))
        #expect(!GroupPermissionRules.canRemove(actor: .admin, target: .admin))
        #expect(!GroupPermissionRules.canRemove(actor: .owner, target: .owner))
        #expect(GroupPermissionRules.canManageInvites(.admin))
        #expect(!GroupPermissionRules.canManageInvites(.member))
        #expect(GroupPermissionRules.canChangeRoles(.owner))
        #expect(!GroupPermissionRules.canChangeRoles(.admin))
        #expect(GroupPermissionRules.canEditSettings(.owner))
        #expect(!GroupPermissionRules.canEditSettings(.admin))
        #expect(GroupPermissionRules.canDelete(.owner))
        #expect(!GroupPermissionRules.canDelete(.admin))
        #expect(!GroupPermissionRules.canDelete(.member))
    }

    @Test func ownerCanDeleteGroupAndNonOwnerCannot() throws {
        var snapshot = DemoSeed.make()
        let ownedGroupID = snapshot.groups.first { $0.ownerID == snapshot.currentUser.id }!.id
        let otherGroupID = snapshot.groups.first { $0.ownerID != snapshot.currentUser.id }!.id

        #expect(throws: RepositoryError.self) {
            try SnapshotCommandApplier.apply(.deleteGroup(otherGroupID), to: snapshot)
        }

        let (updated, _) = try SnapshotCommandApplier.apply(.deleteGroup(ownedGroupID), to: snapshot)
        #expect(!updated.groups.contains { $0.id == ownedGroupID })
        #expect(!updated.memberships.contains { $0.groupID == ownedGroupID })
        #expect(!updated.challenges.contains { $0.groupID == ownedGroupID })
        #expect(!updated.activity.contains { $0.groupID == ownedGroupID })
        #expect(updated.groups.contains { $0.id == otherGroupID })
    }

    private func entry(_ name: String, points: Int, completed: Int, longest: Int, achieved: Date) -> LeaderboardEntry {
        let user = CahootsUser(id: UUID(), appleSubjectID: nil, displayName: name, avatarPath: nil, timezoneIdentifier: "UTC", createdAt: .now, updatedAt: .now, deletedAt: nil, showsExactTotals: false)
        return LeaderboardEntry(user: user, points: points, completedRequirements: completed, scheduledRequirements: 10, currentStreak: longest, longestStreak: longest, finalScoreAchievedAt: achieved, previousRank: nil)
    }
}

struct WorkoutClipPathRulesTests {
    @Test func acceptsCanonicalStoragePath() {
        let groupID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let challengeID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let userID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let clipID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9))!
        let path = "\(groupID.uuidString.lowercased())/\(challengeID.uuidString.lowercased())/2026-09-09/\(userID.uuidString.lowercased())/\(clipID.uuidString.lowercased()).mov"
        #expect(WorkoutClipPathRules.isValid(
            storagePath: path,
            groupID: groupID,
            challengeID: challengeID,
            userID: userID,
            requirementDate: date
        ))
    }

    @Test func acceptsSwiftUppercaseUUIDStoragePath() {
        let groupID = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        let challengeID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let userID = UUID(uuidString: "99999999-8888-4777-8666-555555555555")!
        let clipID = UUID(uuidString: "abcdefab-cdef-4abc-8def-abcdefabcdef")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        // Mirrors clip-upload-url before lowercase normalization: Swift uuidString is uppercase.
        let path = "\(groupID.uuidString)/\(challengeID.uuidString)/2026-09-10/\(userID.uuidString)/\(clipID.uuidString).mov"
        #expect(path != path.lowercased())
        #expect(WorkoutClipPathRules.isValid(
            storagePath: path,
            groupID: groupID,
            challengeID: challengeID,
            userID: userID,
            requirementDate: date
        ))
    }

    @Test func rejectsWrongUserOrExtensionOrTraversal() {
        let groupID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let challengeID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let userID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let otherUser = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9))!
        let prefix = "\(groupID.uuidString.lowercased())/\(challengeID.uuidString.lowercased())/2026-09-09"

        #expect(!WorkoutClipPathRules.isValid(
            storagePath: "\(prefix)/\(otherUser.uuidString.lowercased())/clip.mov",
            groupID: groupID,
            challengeID: challengeID,
            userID: userID,
            requirementDate: date
        ))
        #expect(!WorkoutClipPathRules.isValid(
            storagePath: "\(prefix)/\(userID.uuidString.lowercased())/clip.mp4",
            groupID: groupID,
            challengeID: challengeID,
            userID: userID,
            requirementDate: date
        ))
        #expect(!WorkoutClipPathRules.isValid(
            storagePath: "\(prefix)/\(userID.uuidString.lowercased())/../evil.mov",
            groupID: groupID,
            challengeID: challengeID,
            userID: userID,
            requirementDate: date
        ))
    }
}

struct AppleSignInNonceTests {
    @Test func sha256IsDeterministicForKnownInput() {
        #expect(AppleSignInNonce.sha256("hello") == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test func randomNonceIsLongEnough() {
        #expect(AppleSignInNonce.random().count >= 32)
        #expect(AppleSignInNonce.random(length: 40).count == 40)
    }
}

struct AppDefaultsTests {
    @Test func migratesLegacyOnboardingAndActiveGroupKeys() {
        let suite = "cahoots.tests.appDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: AppDefaults.legacyOnboardingComplete)
        defaults.set("11111111-1111-1111-1111-111111111111", forKey: AppDefaults.legacyActiveGroupID)

        AppDefaults.migrateLegacyKeysIfNeeded(defaults: defaults)

        #expect(defaults.bool(forKey: AppDefaults.onboardingComplete) == true)
        #expect(defaults.string(forKey: AppDefaults.activeGroupID) == "11111111-1111-1111-1111-111111111111")
        #expect(defaults.object(forKey: AppDefaults.legacyOnboardingComplete) == nil)
        #expect(defaults.object(forKey: AppDefaults.legacyActiveGroupID) == nil)
    }
}
