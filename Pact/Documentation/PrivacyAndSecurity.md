# Privacy and security

- Groups are private and invite-only; there is no discovery, public profile search, chat, upload, or location surface.
- Challenges, standings, results, activity, submissions, and recovery usage are projected only for the selected active membership.
- Check-in UUIDs and stable scoring keys make accepted scoring idempotent. Rejected submissions remain visible to the submitting user without provisional points.
- Exact workout quantities and proof clips are omitted from group activity copy and all lock-screen notification copy until the viewer has checked in, used a recovery day, or the daily deadline has passed.
- Short private workout proof clips are stored for the current requirement day and retained for up to seven days or until the round ends; they are never shared publicly or saved to the Camera Roll by Round.
- Blocking hides the blocked user’s activity and prevents joining through an invite created by that user. Reporting requires a category and sanitizes optional details.
- Owner/admin/member permissions are checked before governance mutations. The owner cannot be removed; ownership transfer makes the previous owner an admin.
- Sign-in tokens use Keychain. Support, privacy, terms, bundle identity, and invite host come from build configuration rather than hard-coded production values.
- `PrivacyInfo.xcprivacy` declares UserDefaults required-reason access (`CA92.1`), no tracking, and no SDK-collected data. Re-audit the manifest whenever new frameworks or required-reason APIs are introduced.
- Unified logs use public counts/status and private error details. MetricKit is first-party diagnostics only; no third-party analytics SDK was added.

Before production, complete a backend/RLS security review, rate limits and abuse monitoring, retention/deletion SLAs, incident response, legal review, App Privacy answers, and physical-device entitlement testing.
