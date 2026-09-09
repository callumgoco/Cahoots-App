# Demo mode

Demo mode is automatic when live configuration is absent. It requires no account, API key, network, or external service.

The v3 seed contains two distinct joined groups: **Saturday Crew** and **Lunch Break Club**. Each has group-scoped membership, challenges, standings, activity, invitations, and notification controls. The seed also includes an active challenge, peer proof check-ins for today (so spoilers are visible), an open vote, a completed round result, and an optional waiting offline check-in so lifecycle, switching, and queue states are immediately testable.

Creating/joining/selecting groups, proposals, vote changes, check-ins, accepted/rejected history, governance actions, invite rotation, appearance, and notification settings mutate the same versioned local snapshot and persist through SwiftData. Corrupt stored data is not replaced by this seed without an explicit reset.

Useful test arguments:

- `-skipOnboarding`: enters the app shell.
- `-resetDemo`: restores the v3 seed and clears the selected-group preference.
- `-ephemeralData`: uses an in-memory store.
- `-emptyDemo`: removes the current user’s active memberships.
- `-noProposal`: removes open proposals for builder tests.
- `-forceOffline`: forces the offline check-in path.
- `-suppressNotificationPrimer`: prevents an unrelated system-permission flow during UI tests.

Do not treat demo membership, scores, reports, or moderation actions as production data.
