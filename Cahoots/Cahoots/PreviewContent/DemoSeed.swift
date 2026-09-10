import Foundation

enum DemoSeed {
    static func make(
        now: Date = .now,
        includePendingSubmission: Bool = ProcessInfo.processInfo.arguments.contains("-seedPendingSync")
    ) -> DemoSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        let today = calendar.startOfDay(for: now)
        let createdAt = calendar.date(byAdding: .month, value: -2, to: today) ?? today

        let you = CahootsUser(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(), appleSubjectID: nil, displayName: "Alex Chen", avatarPath: nil, timezoneIdentifier: "Europe/London", createdAt: createdAt, updatedAt: now, deletedAt: nil, showsExactTotals: false)
        let jennifer = user("Jennifer Hale", index: 2, createdAt: createdAt, now: now)
        let marcus = user("Marcus Lee", index: 3, createdAt: createdAt, now: now)
        let priya = user("Priya Shah", index: 4, createdAt: createdAt, now: now)
        let alex = user("Alex Morgan", index: 5, createdAt: createdAt, now: now)
        let casey = user("Casey Park", index: 6, createdAt: createdAt, now: now)
        let users = [you, jennifer, marcus, priya, alex, casey]

        let groupID = UUID(uuidString: "10000000-0000-0000-0000-000000000001") ?? UUID()
        let group = CahootsGroup(id: groupID, name: "Saturday Crew", emoji: "⚡️", ownerID: jennifer.id, memberLimit: 12, createdAt: createdAt, updatedAt: now, archivedAt: nil)
        let memberships = users.enumerated().map { offset, member in
            GroupMembership(id: UUID(), groupID: groupID, userID: member.id, role: offset == 1 ? .owner : (offset == 0 ? .admin : .member), status: .active, joinedAt: createdAt.addingTimeInterval(Double(offset) * 600), leftAt: nil, notificationLevel: .immediate)
        }

        let challengeID = UUID(uuidString: "20000000-0000-0000-0000-000000000001") ?? UUID()
        let start = calendar.date(byAdding: .day, value: -12, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 17, to: today) ?? today
        let saturdayDeadlineMinutes: Int = {
            if ProcessInfo.processInfo.arguments.contains("-deadlineSoon") {
                let soon = now.addingTimeInterval(90)
                let minutes = calendar.dateComponents([.hour, .minute], from: today, to: soon)
                let total = (minutes.hour ?? 0) * 60 + (minutes.minute ?? 0)
                return min(23 * 60 + 59, max(1, total))
            }
            return 23 * 60 + 59
        }()
        let challenge = CahootsChallenge(id: challengeID, groupID: groupID, proposalID: nil, title: "30-Day Push-Up Challenge", activityType: "push-ups", measurementType: .repetitions, minimumQuantity: 15, frequencyType: .daily, scheduledWeekdays: Set(1...7), timesPerWeek: nil, startDate: start, endDate: end, challengeTimezone: "Europe/London", dailyDeadlineMinutes: saturdayDeadlineMinutes, recoveryDayAllowance: 2, status: .active, scoringVersion: 1, createdAt: start)

        let secondGroupID = UUID(uuidString: "10000000-0000-0000-0000-000000000002") ?? UUID()
        let secondGroup = CahootsGroup(id: secondGroupID, name: "Lunch Break Club", emoji: "🌿", ownerID: you.id, memberLimit: 8, createdAt: createdAt.addingTimeInterval(-86_400), updatedAt: now, archivedAt: nil)
        let secondMemberships = [you, priya, casey].enumerated().map { index, member in
            GroupMembership(id: UUID(), groupID: secondGroupID, userID: member.id, role: index == 0 ? .owner : .member, status: .active, joinedAt: createdAt.addingTimeInterval(-86_400 + Double(index) * 600), leftAt: nil, notificationLevel: .immediate)
        }
        let secondChallengeID = UUID(uuidString: "20000000-0000-0000-0000-000000000002") ?? UUID()
        let secondChallenge = CahootsChallenge(id: secondChallengeID, groupID: secondGroupID, proposalID: nil, title: "Lunch Walk Challenge", activityType: "walking minutes", measurementType: .minutes, minimumQuantity: 20, frequencyType: .selectedWeekdays, scheduledWeekdays: [2, 3, 4, 5, 6], timesPerWeek: nil, startDate: start, endDate: end, challengeTimezone: "Europe/London", dailyDeadlineMinutes: 14 * 60, recoveryDayAllowance: 1, status: .active, scoringVersion: 1, createdAt: start)

        let points = [1028, 1236, 1115, 980, 848, 721]
        let completed = [10, 12, 11, 9, 8, 7]
        let streaks = [6, 12, 8, 4, 3, 2]
        let leaderboard = users.enumerated().map { index, member in
            LeaderboardEntry(user: member, points: points[index], completedRequirements: completed[index], scheduledRequirements: 13, currentStreak: streaks[index], longestStreak: max(streaks[index], completed[index]), finalScoreAchievedAt: now.addingTimeInterval(Double(index) * -1_400), previousRank: [4, 1, 2, 3, 5, 6][index], groupID: groupID, challengeID: challengeID)
        }
        let allTime = leaderboard.enumerated().map { index, entry in
            var copy = entry
            copy.points += [3120, 3400, 2900, 2700, 2400, 2100][index]
            copy.completedRequirements += [29, 32, 27, 25, 23, 20][index]
            copy.scheduledRequirements += 35
            return copy
        }
        let secondLeaderboard = [you, priya, casey].enumerated().map { index, member in
            LeaderboardEntry(
                user: member,
                points: [0, 710, 515][index],
                completedRequirements: [0, 7, 5][index],
                scheduledRequirements: 9,
                currentStreak: [0, 5, 2][index],
                longestStreak: [0, 7, 4][index],
                finalScoreAchievedAt: now.addingTimeInterval(Double(index) * -900),
                previousRank: [2, 1, 3][index],
                groupID: secondGroupID,
                challengeID: secondChallengeID
            )
        }
        let secondAllTime = secondLeaderboard.map { entry in
            var copy = entry
            copy.challengeID = nil
            copy.points += 1_200
            copy.completedRequirements += 12
            copy.scheduledRequirements += 15
            return copy
        }

        let proposalID = UUID(uuidString: "30000000-0000-0000-0000-000000000001") ?? UUID()
        let proposal = ChallengeProposal(id: proposalID, groupID: groupID, proposedBy: marcus.id, title: "Morning Mobility", activityType: "stretching minutes", measurementType: .minutes, minimumQuantity: 10, frequencyType: .selectedWeekdays, scheduledWeekdays: [2, 4, 6], durationDays: 21, proposedStartDate: end.addingTimeInterval(86_400), challengeTimezone: "Europe/London", dailyDeadlineMinutes: 21 * 60, recoveryDayAllowance: 1, votingStartsAt: now.addingTimeInterval(-8 * 3_600), votingEndsAt: now.addingTimeInterval(40 * 3_600), eligibleVoterIDs: Set(users.map(\.id)), status: .voting, createdAt: now.addingTimeInterval(-8 * 3_600))
        let votes = [
            Vote(id: UUID(), proposalID: proposalID, userID: marcus.id, choice: .accept, createdAt: now.addingTimeInterval(-7_000), updatedAt: now.addingTimeInterval(-7_000)),
            Vote(id: UUID(), proposalID: proposalID, userID: priya.id, choice: .accept, createdAt: now.addingTimeInterval(-5_000), updatedAt: now.addingTimeInterval(-5_000))
        ]

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let pendingClip = WorkoutClip(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000001") ?? UUID(),
            kind: .set, durationSeconds: 8, localFilename: "demo-pending.set.mov", remotePath: nil, createdAt: yesterday
        )
        let pendingSubmission = Submission(
            id: UUID(), clientGeneratedID: UUID(uuidString: "40000000-0000-0000-0000-000000000001") ?? UUID(),
            challengeID: challengeID, userID: you.id, requirementDate: yesterday, quantity: 15,
            measurementType: .repetitions, completedAt: yesterday.addingTimeInterval(18 * 3_600),
            submittedAt: yesterday.addingTimeInterval(18 * 3_600), syncState: .waiting,
            verificationState: .honourSystem, createdAt: yesterday, updatedAt: yesterday, clips: [pendingClip]
        )
        let pendingOperation = PendingSyncOperation(id: UUID(), clientGeneratedID: pendingSubmission.clientGeneratedID, kind: .submission, retryCount: 1, nextRetryAt: now.addingTimeInterval(300), createdAt: yesterday, lastError: nil)

        let jenniferTodayClip = WorkoutClip(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000002") ?? UUID(),
            kind: .set, durationSeconds: 12, localFilename: "demo-jennifer.set.mov", remotePath: "demo/jennifer/set.mov", createdAt: now.addingTimeInterval(-1_200)
        )
        let jenniferToday = Submission(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000002") ?? UUID(),
            clientGeneratedID: UUID(uuidString: "40000000-0000-0000-0000-000000000012") ?? UUID(),
            challengeID: challengeID, userID: jennifer.id, requirementDate: today, quantity: 20,
            measurementType: .repetitions, completedAt: now.addingTimeInterval(-1_200),
            submittedAt: now.addingTimeInterval(-1_200), syncState: .synced, verificationState: .accepted,
            createdAt: now.addingTimeInterval(-1_200), updatedAt: now.addingTimeInterval(-1_200), clips: [jenniferTodayClip]
        )
        let priyaTodayClip = WorkoutClip(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000003") ?? UUID(),
            kind: .set, durationSeconds: 9, localFilename: "demo-priya.set.mov", remotePath: "demo/priya/set.mov", createdAt: now.addingTimeInterval(-3_400)
        )
        let priyaToday = Submission(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000003") ?? UUID(),
            clientGeneratedID: UUID(uuidString: "40000000-0000-0000-0000-000000000013") ?? UUID(),
            challengeID: challengeID, userID: priya.id, requirementDate: today, quantity: 18,
            measurementType: .repetitions, completedAt: now.addingTimeInterval(-3_400),
            submittedAt: now.addingTimeInterval(-3_400), syncState: .synced, verificationState: .accepted,
            createdAt: now.addingTimeInterval(-3_400), updatedAt: now.addingTimeInterval(-3_400), clips: [priyaTodayClip]
        )

        let activity: [ActivityFeedItem] = [
            item(groupID, jennifer, .completion, "Jennifer completed today’s challenge.", now.addingTimeInterval(-1_200)),
            item(groupID, priya, .completion, "Priya completed today’s challenge.", now.addingTimeInterval(-3_400)),
            item(groupID, marcus, .proposal, "Marcus proposed Morning Mobility.", now.addingTimeInterval(-8 * 3_600)),
            item(groupID, alex, .recovery, "Alex used a recovery day.", now.addingTimeInterval(-25 * 3_600)),
            item(groupID, casey, .memberJoined, "Casey joined Saturday Crew.", now.addingTimeInterval(-8 * 86_400))
        ]
        let secondActivity: [ActivityFeedItem] = [
            item(secondGroupID, priya, .completion, "Priya completed today’s challenge.", now.addingTimeInterval(-2_100)),
            item(secondGroupID, casey, .completion, "Casey completed today’s challenge.", now.addingTimeInterval(-5_100)),
            item(secondGroupID, you, .challengeStarted, "Lunch Walk Challenge has started.", start)
        ]

        let invite = GroupInvite(id: UUID(), groupID: groupID, code: "CAHOOT", createdBy: jennifer.id, expiresAt: now.addingTimeInterval(14 * 86_400), maximumUses: 12, useCount: 6, revokedAt: nil)
        let secondInvite = GroupInvite(id: UUID(), groupID: secondGroupID, code: "MOVE24", createdBy: you.id, expiresAt: now.addingTimeInterval(14 * 86_400), maximumUses: 8, useCount: 3, revokedAt: nil)
        let preference = NotificationPreference(id: UUID(), userID: you.id, groupID: groupID, personalRemindersEnabled: true, friendActivityMode: .immediate, challengeUpdatesEnabled: true, quietHoursStart: 22 * 60, quietHoursEnd: 7 * 60, reminderMinutes: 18 * 60)
        let notificationSettings = UserNotificationSettings(quietHoursStart: 22 * 60, quietHoursEnd: 7 * 60, defaultReminderMinutes: 18 * 60, primerDismissed: false, groups: [.defaults(groupID: groupID), .defaults(groupID: secondGroupID)])
        let previousTop = LeaderboardEngine.ranked(Array(allTime.prefix(3)))
        let previous = PreviousChallengeSummary(id: UUID(), title: "Spring Squat Challenge", winnerName: "Jennifer Hale", topThree: previousTop, totalCompletions: 146, personalBest: 18)
        let previousResult = CahootsResult(id: previous.id, groupID: groupID, challengeID: UUID(uuidString: "20000000-0000-0000-0000-000000000099") ?? UUID(), title: previous.title, winnerName: previous.winnerName, topThree: previous.topThree, members: previous.topThree.map { .init(user: $0.user, completionRate: $0.completionPercentage, points: $0.points, longestStreak: $0.longestStreak) }, totalCompletions: previous.totalCompletions, personalBest: previous.personalBest, completedAt: createdAt)

        var submissions: [Submission] = [jenniferToday, priyaToday]
        if includePendingSubmission { submissions.append(pendingSubmission) }

        return DemoSnapshot(
            schemaVersion: 3, currentUser: you, users: users, groups: [group, secondGroup],
            memberships: memberships + secondMemberships, invites: [invite, secondInvite],
            challenges: [challenge, secondChallenge], proposals: [proposal], votes: votes,
            submissions: submissions, scoreEvents: [], leaderboard: leaderboard + secondLeaderboard,
            allTimeLeaderboard: allTime + secondAllTime, activity: activity + secondActivity,
            notificationPreference: preference, notificationSettings: notificationSettings,
            pendingOperations: includePendingSubmission ? [pendingOperation] : [],
            previousRound: previous, roundResults: [previousResult], appearance: .system
        )
    }

    private static func user(_ name: String, index: Int, createdAt: Date, now: Date) -> CahootsUser {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID()
        return CahootsUser(id: id, appleSubjectID: nil, displayName: name, avatarPath: nil, timezoneIdentifier: "Europe/London", createdAt: createdAt, updatedAt: now, deletedAt: nil, showsExactTotals: false)
    }

    private static func item(_ groupID: UUID, _ actor: CahootsUser, _ type: ActivityEventType, _ message: String, _ date: Date) -> ActivityFeedItem {
        ActivityFeedItem(id: UUID(), groupID: groupID, actorID: actor.id, actorName: actor.displayName, eventType: type, message: message, createdAt: date)
    }
}
