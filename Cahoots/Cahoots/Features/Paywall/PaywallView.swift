import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProduct: PlusProductID = .annual
    @State private var offers: [PlusProductOffer] = []
    @State private var isLoadingOffers = true
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var confirmLeave = false

    private var context: PaywallContext {
        store.paywallContext ?? .manage
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text("More crews with Plus")
                            .font(.largeTitle.bold())
                        Text(contextLine)
                            .foregroundStyle(AppColors.secondaryInk)
                    }

                    CahootsCard(elevated: true) {
                        VStack(alignment: .leading, spacing: AppSpacing.medium) {
                            benefitRow("person.3.fill", "Join or create more than one crew")
                            benefitRow("arrow.left.arrow.right", "Keep streaks and leaderboards separate")
                            benefitRow("switch.2", "Switch crews anytime")
                        }
                    }

                    if isLoadingOffers {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 88)
                    } else if offers.isEmpty {
                        Text("Plus plans aren’t available right now. Check your connection and try again.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.secondaryInk)
                    } else {
                        VStack(spacing: AppSpacing.small) {
                            ForEach(offers, id: \.id) { offer in
                                productButton(offer, badge: offer.id == .annual
                                              ? String(localized: "Best value")
                                              : nil)
                            }
                        }
                    }

                    if let statusMessage {
                        Label(statusMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.danger)
                    }

                    Button {
                        Task { await purchase() }
                    } label: {
                        if isWorking {
                            ProgressView()
                                .tint(AppColors.onInk)
                                .frame(maxWidth: .infinity, minHeight: 54)
                        } else {
                            Text(subscribeTitle)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isWorking || offers.isEmpty)
                    .accessibilityIdentifier("paywall.subscribe")

                    Button("Restore purchases") {
                        Task { await restore() }
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(isWorking)
                    .accessibilityIdentifier("paywall.restore")

                    if showsEscapeHatch {
                        Button(escapeTitle) {
                            confirmLeave = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(isWorking)
                        .accessibilityIdentifier("paywall.leaveAndSwitch")
                    }

                    legalFooter
                }
                .padding(AppSpacing.page)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        store.dismissPaywall()
                        dismiss()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .roundPage()
            .task { await loadOffers() }
            .sheet(isPresented: $confirmLeave) {
                CahootsConfirmationSheet(
                    title: leaveConfirmTitle,
                    message: leaveConfirmMessage,
                    confirmTitle: "Leave and continue",
                    isWorking: isWorking,
                    onConfirm: { Task { await leaveAndContinue() } },
                    onCancel: { confirmLeave = false }
                )
            }
        }
    }

    private var subscribeTitle: String {
        if let offer = offers.first(where: { $0.id == selectedProduct }), offer.hasFreeTrial {
            return String(localized: "Start free trial")
        }
        return String(localized: "Subscribe to Plus")
    }

    private var contextLine: String {
        switch context {
        case .create:
            String(localized: "Free includes one crew. Plus unlocks up to ten.")
        case .join:
            String(localized: "You’ve been invited to another crew. Plus lets you stay in both.")
        case .manage:
            String(localized: "Run multiple friend groups without mixing the competition.")
        }
    }

    private var showsEscapeHatch: Bool {
        switch context {
        case .create, .join: store.currentGroup != nil
        case .manage: false
        }
    }

    private var leaveConfirmTitle: String {
        let name = store.currentGroup?.name ?? String(localized: "your current crew")
        switch context {
        case .join:
            return String(localized: "Leave \(name) to join another crew?")
        case .create:
            return String(localized: "Leave \(name) to create another crew?")
        case .manage:
            return String(localized: "Leave \(name)?")
        }
    }

    private var leaveConfirmMessage: String {
        switch context {
        case .join:
            return String(localized: "You’ll leave this crew and join the invited one. You won’t stay in both.")
        case .create:
            return String(localized: "You’ll leave this crew, then start a new one. You won’t stay in both.")
        case .manage:
            return String(localized: "You’ll lose access to this crew’s rounds and activity.")
        }
    }

    private var escapeTitle: String {
        let name = store.currentGroup?.name ?? String(localized: "current crew")
        switch context {
        case .join:
            return String(localized: "Leave \(name) and join instead")
        case .create:
            return String(localized: "Leave \(name) and create instead")
        case .manage:
            return ""
        }
    }

    private func benefitRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            Image(systemName: symbol)
                .font(.body.bold())
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func productButton(_ offer: PlusProductOffer, badge: String?) -> some View {
        let isSelected = selectedProduct == offer.id
        return Button {
            selectedProduct = offer.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppSpacing.small) {
                        Text(offer.displayName)
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    (isSelected ? AppColors.onInk.opacity(0.18) : AppColors.accentSoft),
                                    in: Capsule()
                                )
                                .foregroundStyle(isSelected ? AppColors.onInk : AppColors.ink)
                        }
                    }
                    Text(offer.priceText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? AppColors.onInk.opacity(0.72) : AppColors.secondaryInk)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppColors.onInk : AppColors.ink)
            }
            .padding(AppSpacing.medium)
            .foregroundStyle(isSelected ? AppColors.onInk : AppColors.ink)
            .background(
                isSelected ? AppColors.ink : AppColors.chip,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColors.ink : AppColors.ink.opacity(0.14),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall.product.\(offer.id.rawValue)")
    }

    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Payment is charged to your Apple ID. Subscriptions renew unless cancelled at least 24 hours before the period ends. Manage in Settings → Apple ID → Subscriptions.")
                .font(.caption2)
                .foregroundStyle(AppColors.secondaryInk)
            HStack(spacing: AppSpacing.medium) {
                if let terms = AppIdentity.termsURL {
                    Link("Terms", destination: terms)
                }
                if let privacy = AppIdentity.privacyURL {
                    Link("Privacy", destination: privacy)
                }
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func loadOffers() async {
        isLoadingOffers = true
        let loaded = await store.loadPlusProductOffers()
        offers = loaded
        if let annual = loaded.first(where: { $0.id == .annual }) {
            selectedProduct = annual.id
        } else if let first = loaded.first {
            selectedProduct = first.id
        }
        isLoadingOffers = false
    }

    private func purchase() async {
        isWorking = true
        statusMessage = nil
        if let error = await store.purchasePlus(selectedProduct) {
            statusMessage = error
        } else if store.effectiveEntitlement.hasPlusAccess {
            store.dismissPaywall()
            dismiss()
        }
        isWorking = false
    }

    private func restore() async {
        isWorking = true
        statusMessage = nil
        if let error = await store.restorePlusPurchases() {
            statusMessage = error
        } else if store.effectiveEntitlement.hasPlusAccess {
            store.dismissPaywall()
            dismiss()
        }
        isWorking = false
    }

    private func leaveAndContinue() async {
        isWorking = true
        statusMessage = nil
        let ctx = context
        if let error = await store.leaveCurrentCrewAndContinue(context: ctx) {
            statusMessage = error
            isWorking = false
            confirmLeave = false
            return
        }
        confirmLeave = false
        switch ctx {
        case .create:
            dismiss()
        case .join, .manage:
            dismiss()
        }
        isWorking = false
    }
}
