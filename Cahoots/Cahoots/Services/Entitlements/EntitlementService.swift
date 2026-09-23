import Foundation
import StoreKit

protocol EntitlementService: AnyObject {
    func currentEntitlement() async -> Entitlement
    func membershipLimit() async -> Int
    func purchase(_ productID: PlusProductID) async throws
    func restore() async throws
    /// Latest signed transaction JWS for server sync, if any.
    func latestSignedTransactionJWS() async -> String?
}

extension EntitlementService {
    func membershipLimit() async -> Int {
        await currentEntitlement().membershipLimit
    }

    func purchase(_ productID: PlusProductID) async throws {}
    func restore() async throws {}
    func latestSignedTransactionJWS() async -> String? { nil }
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
