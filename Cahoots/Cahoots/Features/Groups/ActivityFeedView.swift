import SwiftUI

struct ActivityFeedView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.medium) {
                ForEach(store.currentActivity) { item in
                    CahootsCard {
                        ActivityRow(item: item)
                    }
                }
            }
            .padding(AppSpacing.page)
            .cahootsTabBarClearance()
        }
        .navigationTitle("Activity")
        .cahootsDrillInBar()
        .overlay {
            if store.currentActivity.isEmpty {
                ContentUnavailableView("No group activity yet", systemImage: "waveform.path.ecg", description: Text("Private, quantity-free updates will appear here."))
            }
        }
        .roundPage()
    }
}

struct ActivityRow: View {
    let item: ActivityFeedItem

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: symbol)
                .font(.body.bold())
                .foregroundStyle(symbolForeground)
                .frame(width: 38, height: 38)
                .background(symbolBackground, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(item.message).font(.subheadline.weight(.medium))
                Text(relativeTimestamp(item.createdAt)).font(.caption).foregroundStyle(AppColors.secondaryInk)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        let minute: TimeInterval = 60
        let hour = 60 * minute
        let day = 24 * hour
        if interval < minute {
            return String(localized: "Just now")
        }
        if interval < hour {
            let minutes = Int(interval / minute)
            return minutes == 1 ? String(localized: "1 min") : String(localized: "\(minutes) mins")
        }
        if interval < day {
            let hours = Int(interval / hour)
            return hours == 1 ? String(localized: "1 hr") : String(localized: "\(hours) hrs")
        }
        let days = Int(interval / day)
        return days == 1 ? String(localized: "1 day") : String(localized: "\(days) days")
    }

    private var symbol: String {
        switch item.eventType {
        case .completion: "checkmark"
        case .recovery: "moon.zzz.fill"
        case .proposal: "doc.badge.plus"
        case .voteCompleted: "checkmark.seal.fill"
        case .challengeStarted: "flag.fill"
        case .roundFinished: "trophy.fill"
        case .memberJoined: "person.badge.plus"
        }
    }

    private var symbolBackground: Color {
        switch item.eventType {
        case .completion: AppColors.success.opacity(0.28)
        case .recovery: AppColors.secondaryInk.opacity(0.18)
        case .voteCompleted, .proposal: AppColors.accentSoft
        case .challengeStarted, .roundFinished: AppColors.ink.opacity(0.14)
        case .memberJoined: AppColors.chip
        }
    }

    private var symbolForeground: Color {
        switch item.eventType {
        case .completion: AppColors.success
        case .recovery: AppColors.secondaryInk
        default: AppColors.ink
        }
    }
}
