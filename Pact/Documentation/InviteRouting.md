# Invite routing

Round accepts production links in this form:

```text
https://<ROUND_INVITE_HOST>/join/ABC123
```

Development builds also accept `round://join/ABC123`. Codes must be exactly six alphanumeric characters. The app validates the configured host and path, retains a valid pending route through onboarding/authentication, and always asks for confirmation before joining.

## Universal-link deployment

The production invite host must serve an unsigned JSON file at:

```text
https://<ROUND_INVITE_HOST>/.well-known/apple-app-site-association
```

Use the production Apple team ID and bundle ID:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAM_ID.BUNDLE_ID"],
        "components": [
          { "/": "/join/*", "comment": "Round group invitations" }
        ]
      }
    ]
  }
}
```

Serve it as `application/json` without redirects. The Xcode entitlement is generated from `applinks:$(ROUND_INVITE_HOST)`. After deployment, test cold launch, warm launch, onboarding handoff, malformed codes, expired invites, existing membership, and removed-member errors on a physical device.
