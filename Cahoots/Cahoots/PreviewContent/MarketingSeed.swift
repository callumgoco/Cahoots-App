import Foundation

/// Screenshot-ready crew. Check-ins are real submissions so streak reconciliation
/// keeps the standings App Store shots depend on.
enum MarketingSeed {
    static func make(now: Date = .now) -> DemoSnapshot {
        var snapshot = DemoSeed.make(now: now, includePendingSubmission: false)
        let challengeID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")
        let groupID = UUID(uuidString: "10000000-0000-0000-0000-000000000001") ?? UUID()
        guard let challenge = snapshot.challenges.first(where: { $0.id == challengeID }),
              let calendar = ScheduleEngine.calendar(for: challenge) else {
            return snapshot
        }

        let today = calendar.startOfDay(for: now)
        let scheduled = ScheduleEngine.scheduledDates(for: challenge, through: today)
        let past = scheduled.filter { calendar.startOfDay(for: $0) < today }
        let minimum = challenge.minimumQuantity

        let plans: [String: MemberPlan] = [
            "Jennifer Hale": MemberPlan(pastDays: past.count, checkedInToday: true, quantity: 32, previousRank: 2),
            "Alex Chen": MemberPlan(pastDays: max(0, past.count - 1), checkedInToday: true, quantity: 30, previousRank: 3),
            "Marcus Lee": MemberPlan(pastDays: max(0, past.count - 2), checkedInToday: true, quantity: 24, previousRank: 4),
            "Priya Shah": MemberPlan(pastDays: min(8, past.count), checkedInToday: true, quantity: 20, previousRank: 6),
            "Alex Morgan": MemberPlan(pastDays: min(5, past.count), checkedInToday: false, quantity: 18, previousRank: 4),
            "Casey Park": MemberPlan(pastDays: min(3, past.count), checkedInToday: false, quantity: 16, previousRank: 5)
        ]

        let names: [String: String] = [
            "Alex Chen": "Sam Rivera",
            "Jennifer Hale": "Maya Okonkwo",
            "Marcus Lee": "Jordan Hale",
            "Priya Shah": "Priya Shah",
            "Alex Morgan": "Leo Park",
            "Casey Park": "Nina Alvarez"
        ]

        snapshot.submissions.removeAll { $0.challengeID == challenge.id }
        for user in snapshot.users {
            guard let plan = plans[user.displayName] else { continue }
            let days = Array(past.suffix(plan.pastDays))
            for day in days {
                snapshot.submissions.append(submission(
                    user: user, challenge: challenge, day: day, quantity: plan.quantity, calendar: calendar, includeClip: false
                ))
            }
            if plan.checkedInToday {
                snapshot.submissions.append(submission(
                    user: user, challenge: challenge, day: today, quantity: plan.quantity, calendar: calendar, includeClip: user.id != snapshot.currentUser.id
                ))
            }
        }

        let scheduledCount = max(scheduled.count, 1)
        for index in snapshot.leaderboard.indices where snapshot.leaderboard[index].challengeID == challenge.id {
            let original = snapshot.leaderboard[index].user.displayName
            guard let plan = plans[original] else { continue }
            let completed = plan.pastDays + (plan.checkedInToday ? 1 : 0)
            let perDay = ScoringEngine.points(completedQuantity: plan.quantity, minimumQuantity: minimum)
            snapshot.leaderboard[index].points = perDay * completed
            snapshot.leaderboard[index].completedRequirements = completed
            snapshot.leaderboard[index].scheduledRequirements = scheduledCount
            snapshot.leaderboard[index].currentStreak = completed
            snapshot.leaderboard[index].longestStreak = completed
            snapshot.leaderboard[index].previousRank = plan.previousRank
        }

        let historyBonus = [4_860, 4_520, 3_900, 3_100, 2_400, 1_800]
        let roundOrder = ["Jennifer Hale", "Alex Chen", "Marcus Lee", "Priya Shah", "Alex Morgan", "Casey Park"]
        for index in snapshot.allTimeLeaderboard.indices where snapshot.allTimeLeaderboard[index].groupID == groupID {
            let original = snapshot.allTimeLeaderboard[index].user.displayName
            guard let plan = plans[original], let order = roundOrder.firstIndex(of: original) else { continue }
            let completed = plan.pastDays + (plan.checkedInToday ? 1 : 0)
            let perDay = ScoringEngine.points(completedQuantity: plan.quantity, minimumQuantity: minimum)
            snapshot.allTimeLeaderboard[index].points = perDay * completed + historyBonus[order]
            snapshot.allTimeLeaderboard[index].completedRequirements = completed + 40
            snapshot.allTimeLeaderboard[index].scheduledRequirements = scheduledCount + 48
            snapshot.allTimeLeaderboard[index].currentStreak = completed
            snapshot.allTimeLeaderboard[index].longestStreak = completed + 18
        }

        applyNames(&snapshot, names: names)
        if let groupIndex = snapshot.groups.firstIndex(where: { $0.id == groupID }) {
            snapshot.groups[groupIndex].name = "Rise Club"
        }

        if var proposal = snapshot.proposals.first {
            let acceptors = ["Maya Okonkwo", "Jordan Hale", "Priya Shah"]
            snapshot.votes.removeAll { $0.proposalID == proposal.id }
            for name in acceptors {
                guard let user = snapshot.users.first(where: { $0.displayName == name }) else { continue }
                snapshot.votes.append(Vote(
                    id: UUID(),
                    proposalID: proposal.id,
                    userID: user.id,
                    choice: .accept,
                    createdAt: now.addingTimeInterval(-6_000),
                    updatedAt: now.addingTimeInterval(-6_000)
                ))
            }
            proposal.title = "Morning Mobility"
            if let proposalIndex = snapshot.proposals.firstIndex(where: { $0.id == proposal.id }) {
                snapshot.proposals[proposalIndex] = proposal
            }
        }

        if var settings = snapshot.notificationSettings {
            settings.primerDismissed = true
            snapshot.notificationSettings = settings
        }
        snapshot.appearance = .light
        snapshot.activity = activity(snapshot: snapshot, groupID: groupID, now: now) + snapshot.activity.filter { $0.groupID != groupID }
        let standings = LeaderboardEngine.ranked(snapshot.allTimeLeaderboard.filter { $0.groupID == groupID })
        let top = Array(standings.prefix(3))
        if var result = snapshot.roundResults?.first {
            result.winnerName = top.first?.user.displayName ?? "Maya Okonkwo"
            result.title = "Spring Squat Challenge"
            result.topThree = top
            result.members = standings.map {
                MemberChallengeResult(user: $0.user, completionRate: $0.completionPercentage, points: $0.points, longestStreak: $0.longestStreak)
            }
            result.totalCompletions = standings.reduce(0) { $0 + $1.completedRequirements }
            snapshot.roundResults = [result]
            snapshot.previousRound?.winnerName = result.winnerName
            snapshot.previousRound?.title = result.title
            snapshot.previousRound?.topThree = top
            snapshot.previousRound?.totalCompletions = result.totalCompletions
        }
        return snapshot
    }

    private struct MemberPlan {
        let pastDays: Int
        let checkedInToday: Bool
        let quantity: Double
        let previousRank: Int
    }

    private static func applyNames(_ snapshot: inout DemoSnapshot, names: [String: String]) {
        func rename(_ user: inout CahootsUser) {
            if let updated = names[user.displayName] { user.displayName = updated }
        }
        rename(&snapshot.currentUser)
        for index in snapshot.users.indices { rename(&snapshot.users[index]) }
        for index in snapshot.leaderboard.indices { rename(&snapshot.leaderboard[index].user) }
        for index in snapshot.allTimeLeaderboard.indices { rename(&snapshot.allTimeLeaderboard[index].user) }
        if var previous = snapshot.previousRound {
            for index in previous.topThree.indices { rename(&previous.topThree[index].user) }
            snapshot.previousRound = previous
        }
        if var results = snapshot.roundResults {
            for resultIndex in results.indices {
                for index in results[resultIndex].topThree.indices { rename(&results[resultIndex].topThree[index].user) }
                for index in results[resultIndex].members.indices { rename(&results[resultIndex].members[index].user) }
            }
            snapshot.roundResults = results
        }
    }

    private static func submission(
        user: CahootsUser,
        challenge: CahootsChallenge,
        day: Date,
        quantity: Double,
        calendar: Calendar,
        includeClip: Bool
    ) -> Submission {
        let completedAt = calendar.date(byAdding: .hour, value: 7, to: day) ?? day
        let id = UUID()
        let clips: [WorkoutClip] = includeClip ? [
            WorkoutClip(
                id: UUID(),
                kind: .set,
                durationSeconds: 8,
                localFilename: nil,
                remotePath: "demo/\(user.id.uuidString)/set.mov",
                createdAt: completedAt
            )
        ] : []
        return Submission(
            id: id,
            clientGeneratedID: id,
            challengeID: challenge.id,
            userID: user.id,
            requirementDate: day,
            quantity: quantity,
            measurementType: challenge.measurementType,
            completedAt: completedAt,
            submittedAt: completedAt,
            syncState: .synced,
            verificationState: .accepted,
            createdAt: completedAt,
            updatedAt: completedAt,
            clips: clips
        )
    }

    private static func activity(snapshot: DemoSnapshot, groupID: UUID, now: Date) -> [ActivityFeedItem] {
        func actor(_ name: String) -> CahootsUser? {
            snapshot.users.first { $0.displayName == name }
        }
        let lines: [(String, ActivityEventType, String, TimeInterval)] = [
            ("Maya Okonkwo", .completion, "Maya completed today’s challenge.", -1_800),
            ("Jordan Hale", .completion, "Jordan completed today’s challenge.", -4_200),
            ("Priya Shah", .completion, "Priya completed today’s challenge.", -7_500),
            ("Jordan Hale", .proposal, "Jordan proposed Morning Mobility.", -8 * 3_600),
            ("Leo Park", .recovery, "Leo used a recovery day.", -26 * 3_600),
            ("Nina Alvarez", .memberJoined, "Nina joined Rise Club.", -6 * 86_400)
        ]
        return lines.compactMap { name, type, message, offset in
            guard let user = actor(name) else { return nil }
            return ActivityFeedItem(
                id: UUID(),
                groupID: groupID,
                actorID: user.id,
                actorName: user.displayName,
                eventType: type,
                message: message,
                createdAt: now.addingTimeInterval(offset)
            )
        }
    }
}
