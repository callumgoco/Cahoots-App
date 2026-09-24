import Foundation
import StoreKit

struct PlusProductOffer: Sendable, Equatable {
    let id: PlusProductID
    let displayName: String
    let priceText: String
    let hasFreeTrial: Bool
}

protocol EntitlementService: AnyObject {
    func currentEntitlement() async -> Entitlement
    func membershipLimit() async -> Int
    func purchase(_ productID: PlusProductID) async throws
    func restore() async throws
    /// Latest signed transaction JWS for server sync, if any.
    func latestSignedTransactionJWS() async -> String?
    /// StoreKit-localized offers for the paywall. Empty when products are unavailable.
    func plusProductOffers() async -> [PlusProductOffer]
}

extension EntitlementService {
    func membershipLimit() async -> Int {
        await currentEntitlement().membershipLimit
    }

    func purchase(_ productID: PlusProductID) async throws {}
    func restore() async throws {}
    func latestSignedTransactionJWS() async -> String? { nil }
    func plusProductOffers() async -> [PlusProductOffer] { [] }
}

final class FreeEntitlementService: EntitlementService {
    func currentEntitlement() async -> Entitlement { .free }
}

/// Demo / UITest override — unlimited multi-crew without StoreKit.
final class PlusEntitlementService: EntitlementService {
    func currentEntitlement() async -> Entitlement { .plus }
}

@MainActor
final class StoreKitEntitlementService: EntitlementService {
    private var cached: Entitlement = .free
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if let transaction = try? checkVerified(update) {
                    await transaction.finish()
                    await self.refreshFromStore()
                }
            }
        }
        Task { await refreshFromStore() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func currentEntitlement() async -> Entitlement {
        await refreshFromStore()
        return cached
    }

    func membershipLimit() async -> Int {
        await currentEntitlement().membershipLimit
    }

    func purchase(_ productID: PlusProductID) async throws {
        let products = try await Product.products(for: [productID.rawValue])
        guard let product = products.first else {
            throw RepositoryError.server(String(localized: "Plus isn’t available to purchase yet."))
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshFromStore()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async throws {
        try await StoreKit.AppStore.sync()
        await refreshFromStore()
    }

    func latestSignedTransactionJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if PlusProductID(rawValue: transaction.productID) != nil {
                return result.jwsRepresentation
            }
        }
        return nil
    }

    func plusProductOffers() async -> [PlusProductOffer] {
        let ids = PlusProductID.allCases.map(\.rawValue)
        guard let products = try? await Product.products(for: ids), !products.isEmpty else {
            return []
        }
        return PlusProductID.allCases.compactMap { productID in
            guard let product = products.first(where: { $0.id == productID.rawValue }) else {
                return nil
            }
            let intro = product.subscription?.introductoryOffer
            let hasFreeTrial = intro?.paymentMode == .freeTrial
            let priceText: String
            if hasFreeTrial, let intro {
                let period = intro.period
                let trialLabel = Self.trialLabel(unit: period.unit, value: period.value)
                priceText = String(
                    localized: "\(product.displayPrice) / \(Self.periodLabel(for: product)) · \(trialLabel)"
                )
            } else {
                priceText = String(
                    localized: "\(product.displayPrice) / \(Self.periodLabel(for: product))"
                )
            }
            return PlusProductOffer(
                id: productID,
                displayName: product.displayName.isEmpty ? productID.displayName : product.displayName,
                priceText: priceText,
                hasFreeTrial: hasFreeTrial
            )
        }
    }

    private static func periodLabel(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return String(localized: "period")
        }
        switch period.unit {
        case .day:
            return period.value == 1 ? String(localized: "day") : String(localized: "\(period.value) days")
        case .week:
            return period.value == 1 ? String(localized: "week") : String(localized: "\(period.value) weeks")
        case .month:
            return period.value == 1 ? String(localized: "month") : String(localized: "\(period.value) months")
        case .year:
            return period.value == 1 ? String(localized: "year") : String(localized: "\(period.value) years")
        @unknown default:
            return String(localized: "period")
        }
    }

    private static func trialLabel(unit: Product.SubscriptionPeriod.Unit, value: Int) -> String {
        switch unit {
        case .day:
            return value == 1
                ? String(localized: "1-day trial")
                : String(localized: "\(value)-day trial")
        case .week:
            return value == 1
                ? String(localized: "7-day trial")
                : String(localized: "\(value)-week trial")
        case .month:
            return value == 1
                ? String(localized: "1-month trial")
                : String(localized: "\(value)-month trial")
        case .year:
            return value == 1
                ? String(localized: "1-year trial")
                : String(localized: "\(value)-year trial")
        @unknown default:
            return String(localized: "Free trial")
        }
    }

    private func refreshFromStore() async {
        var hasPlus = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if PlusProductID(rawValue: transaction.productID) != nil {
                if let expiration = transaction.expirationDate, expiration <= .now {
                    continue
                }
                if transaction.revocationDate != nil { continue }
                hasPlus = true
                break
            }
        }
        cached = hasPlus ? .plus : .free
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw RepositoryError.server(String(localized: "Couldn’t verify this purchase with Apple."))
        case .verified(let safe):
            return safe
        }
    }
}
