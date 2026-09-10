# Invite routing

Cahoots accepts production links in this form:

```text
https://<CAHOOTS_INVITE_HOST>/join/ABC123
```

Development builds also accept `cahoots://join/ABC123`. Codes must be exactly six alphanumeric characters. The app validates the configured host and path, retains a valid pending route through onboarding/authentication, and always asks for confirmation before joining.

Check-in and vote notification deep links use `cahoots://log/{groupID}` and `cahoots://vote/{groupID}/{proposalID}` (HTTPS equivalents on the invite host are also parsed).

## Universal-link deployment

A checked-in template is at [`web/.well-known/apple-app-site-association`](../web/.well-known/apple-app-site-association). The production invite host must serve that unsigned JSON at:

```text
https://<CAHOOTS_INVITE_HOST>/.well-known/apple-app-site-association
```

Current template (team `PVP9QSJ25G`, bundle `com.callumoconnor.cahoots`):

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["PVP9QSJ25G.com.callumoconnor.cahoots"],
        "components": [
          { "/": "/join/*", "comment": "Cahoots group invitations" },
          { "/": "/log/*", "comment": "Cahoots workout deep links" }
        ]
      }
    ]
  }
}
```

Serve it as `application/json` without redirects. Also host the legal pages in this folder:

- `https://<CAHOOTS_INVITE_HOST>/privacy/` → `web/privacy/index.html`
- `https://<CAHOOTS_INVITE_HOST>/terms/` → `web/terms/index.html`

The Xcode entitlement is generated from `applinks:$(CAHOOTS_INVITE_HOST)`. After deployment, test cold launch, warm launch, onboarding handoff, malformed codes, expired invites, existing membership, and removed-member errors on a physical device.
