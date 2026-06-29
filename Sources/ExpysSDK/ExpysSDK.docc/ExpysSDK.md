# ``ExpysSDK``

The official Expys data SDK for Swift: browse offers, redeem them, check
eligibility, and read the wallet from Apple platforms and server-side Swift.

## Overview

`ExpysSDK` is a small, member-facing client for the Expys API. It is built on
Foundation only (zero external dependencies), is fully `async`/`await`, ships
`Sendable` types, and guards its token state behind an actor. It shares one
contract - method surface, configuration names, error taxonomy, retry and
idempotency semantics, and User-Agent format - with the TypeScript and Kotlin
SDKs.

Configure a client once with a short-lived member token (your backend obtains it
from `POST /v1/auth/exchange`; the Org-API-Key never ships in the app), then call
the member-facing methods:

```swift
import ExpysSDK

let client = ExpysClient(
  configuration: ExpysConfiguration(token: memberToken, environment: .sandbox)
)

let offers = try await client.listOffers(limit: 20)
let redemption = try await client.createRedemption(.init(offer: offers.data[0].id))
let status = try await client.getRedemption(id: redemption.id)
let eligibility = try await client.eligibility()
let wallet = try await client.wallet()
```

Every call retries `429`/`5xx` with full-jitter backoff (honoring `Retry-After`),
refreshes the token proactively near expiry and reactively once on a `401`, and
sends an `Idempotency-Key` on writes.

## Topics

### Getting Started

- ``ExpysClient``
- ``ExpysConfiguration``

### Authentication & Token Refresh

- ``TokenRefresh``
- ``ExpysConfiguration/refreshToken``
- ``ExpysConfiguration/tokenExpiresAt``
- ``ExpysConfiguration/refreshSkew``

### Environments

- ``ExpysEnvironment``
- ``ExpysConfiguration/environment``

### Offers

- ``ExpysClient/listOffers(limit:cursor:)``
- ``Offer``
- ``OfferList``

### Redemptions

- ``ExpysClient/createRedemption(_:idempotencyKey:)``
- ``ExpysClient/getRedemption(id:)``
- ``CreateRedemptionRequest``
- ``Redemption``
- ``generateIdempotencyKey()``

### Eligibility

- ``ExpysClient/eligibility(externalUserID:)``
- ``MemberEligibility``

### Wallet

- ``ExpysClient/wallet()``
- ``Wallet``
- ``Currency``

### Errors

- ``ExpysError``
- ``APIError``

### Retries & Timeouts

- ``ExpysConfiguration/maxRetries``
- ``ExpysConfiguration/timeout``

### Configuration Reference

- ``ExpysConfiguration/token``
- ``ExpysConfiguration/baseURL``
- ``ExpysConfiguration/orgID``
- ``ExpysConfiguration/userAgentSuffix``

### Versioning Policy

- ``ExpysVersion``
```
