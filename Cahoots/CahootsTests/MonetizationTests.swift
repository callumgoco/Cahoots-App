import Foundation
import Testing
@testable import Cahoots

struct MonetizationTests {
    @Test func freeMembershipLimitIsOne() {
        #expect(Entitlement.free.membershipLimit == 1)
        #expect(Entitlement.plus.membershipLimit == 10)
        #expect(Entitlement.groupPro.membershipLimit == 10)
    }

    @Test func plusRequiredMapsToReadableCopy() {
        let message = RepositoryError.readable("plus_required")
        #expect(message.localizedCaseInsensitiveContains("one crew"))
        #expect(message.localizedCaseInsensitiveContains("Plus"))
    }

    @Test func effectiveEntitlementHonoursPreviewWindow() {
        let now = Date()
        let user = CahootsUser(
            id: UUID(),
            displayName: "Alex",
            timezoneIdentifier: "Europe/London",
            createdAt: now,
            updatedAt: now,
            showsExactTotals: false,
            entitlement: .free,
            plusPreviewUntil: now.addingTimeInterval(86_400)
        )
        #expect(user.effectiveEntitlement(at: now) == .plus)
        #expect(user.effectiveEntitlement(at: now.addingTimeInterval(172_800)) == .free)
    }

    @Test func expiredPlusFallsBackToFreeWithoutPreview() {
        let now = Date()
        let user = CahootsUser(
            id: UUID(),
            displayName: "Alex",
            timezoneIdentifier: "Europe/London",
            createdAt: now,
            updatedAt: now,
            showsExactTotals: false,
            entitlement: .plus,
            plusExpiresAt: now.addingTimeInterval(-60)
        )
        #expect(user.effectiveEntitlement(at: now) == .free)
    }

    @Test func freeEntitlementServiceReturnsFree() async {
        let service = FreeEntitlementService()
        #expect(await service.currentEntitlement() == .free)
        #expect(await service.membershipLimit() == 1)
        #expect(await service.plusProductOffers().isEmpty)
    }

    @Test func plusEntitlementServiceReturnsPlus() async {
        let service = PlusEntitlementService()
        #expect(await service.currentEntitlement() == .plus)
        #expect(await service.membershipLimit() == 10)
        #expect(await service.plusProductOffers().isEmpty)
    }
}
