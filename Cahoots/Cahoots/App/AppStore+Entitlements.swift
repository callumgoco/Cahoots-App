import Foundation
import OSLog
import StoreKit
import UIKit

extension AppStore {
    var activeMembershipCount: Int {
        activeGroups.count
    }

    var effectiveEntitlement: Entitlement {
        if let user = snapshot?.currentUser {
            let fromProfile = user.effectiveEntitlement(at: environment.clock.now)
            if fromProfile.hasPlusAccess { return fromProfile }
        }
        return cachedEntitlement
    }

    var crewMembershipLimit: Int {
        effectiveEntitlement.membershipLimit
    }

    var canAddCrewMembership: Bool {
        activeMembershipCount < crewMembershipLimit
    }

    func presentPaywall(_ context: PaywallContext) {
        paywallContext = context
    }

    func dismissPaywall() {
        paywallContext = nil
    }

    func refreshEntitlements() async {
        cachedEntitlement = await environment.entitlements.currentEntitlement()
        if let user = snapshot?.currentUser {
            let profile = user.effectiveEntitlement(at: environment.clock.now)
            if profile.hasPlusAccess {
                cachedEntitlement = profile
            }
        }
        _ = await syncEntitlementToServerIfNeeded()
    }

    func purchasePlus(_ productID: PlusProductID) async -> String? {
        do {
            try await environment.entitlements.purchase(productID)
            await refreshEntitlementsFromStoreOnly()
            if let syncError = await syncEntitlementToServerIfNeeded() {
                return syncError
            }
            guard effectiveEntitlement.hasPlusAccess else {
                return String(localized: "Purchase finished, but Plus isn’t active yet. Try Restore purchases.")
            }
            noticeBanner = String(localized: "You’re on Cahoots Plus.")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func restorePlusPurchases() async -> String? {
        do {
            try await environment.entitlements.restore()
            await refreshEntitlementsFromStoreOnly()
            if let syncError = await syncEntitlementToServerIfNeeded() {
                return syncError
            }
            if effectiveEntitlement.hasPlusAccess {
                noticeBanner = String(localized: "Plus restored.")
                return nil
            }
            return String(localized: "No Plus subscription found for this Apple ID.")
        } catch {
            return error.localizedDescription
        }
    }

    func loadPlusProductOffers() async -> [PlusProductOffer] {
        await environment.entitlements.plusProductOffers()
    }

    @MainActor
    func openManageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else {
            errorBanner = String(localized: "Open Settings → Apple ID → Subscriptions to manage Plus.")
            return
        }
        do {
            try await StoreKit.AppStore.showManageSubscriptions(in: scene)
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    /// Leave the current crew, then create or join so Free users can switch without Plus.
    func leaveCurrentCrewAndContinue(context: PaywallContext) async -> String? {
        guard currentGroup != nil else {
            return String(localized: "You’re not in a crew to leave.")
        }
        let left = await leaveCurrentGroup()
        guard left else {
            return errorBanner ?? String(localized: "Couldn’t leave your current crew.")
        }
        dismissPaywall()
        switch context {
        case .create:
            // Caller presents CreateGroupView after dismiss.
            pendingPaywallContinue = .create
            return nil
        case .join(let code):
            if let message = await joinGroup(code: code) {
                return message
            }
            return nil
        case .manage:
            return nil
        }
    }

    private func refreshEntitlementsFromStoreOnly() async {
        cachedEntitlement = await environment.entitlements.currentEntitlement()
    }

    /// Syncs the latest StoreKit JWS to the server. Returns a user-visible error when live sync fails.
    @discardableResult
    private func syncEntitlementToServerIfNeeded() async -> String? {
        guard environment.repository.mode == .live else { return nil }
        guard let jws = await environment.entitlements.latestSignedTransactionJWS() else { return nil }
        do {
            let entitlement = try await environment.repository.syncEntitlement(signedTransaction: jws)
            cachedEntitlement = entitlement
            if var snapshot, var user = Optional(snapshot.currentUser) {
                user.entitlement = entitlement
                snapshot.currentUser = user
                if let index = snapshot.users.firstIndex(where: { $0.id == user.id }) {
                    snapshot.users[index] = user
                }
                self.snapshot = snapshot
            }
            return nil
        } catch {
            AppLog.lifecycle.error("Entitlement sync failed: \(error.localizedDescription, privacy: .public)")
            let message = String(
                localized: "Purchase succeeded, but we couldn’t unlock Plus on your account. Check your connection and tap Restore purchases."
            )
            errorBanner = message
            return message
        }
    }
}

enum PendingPaywallContinue: Equatable, Sendable {
    case create
}
