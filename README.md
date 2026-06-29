# ExpysSDK (Swift)

[![SDK CI](https://github.com/Utopia-Members-Club-Inc/utopia/actions/workflows/sdk-ci.yml/badge.svg)](https://github.com/Utopia-Members-Club-Inc/utopia/actions/workflows/sdk-ci.yml)
[![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

<!--
The badges below go live once the public `expys-swift` mirror is registered on the
Swift Package Index and the repo is connected to Codecov + CocoaPods Trunk (see
CONTRIBUTING.md and sdk-ci.yml). Uncomment them then.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FUtopia-Members-Club-Inc%2Fexpys-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Utopia-Members-Club-Inc/expys-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FUtopia-Members-Club-Inc%2Fexpys-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Utopia-Members-Club-Inc/expys-swift)
[![codecov](https://codecov.io/gh/Utopia-Members-Club-Inc/utopia/branch/main/graph/badge.svg?flag=sdk-swift)](https://codecov.io/gh/Utopia-Members-Club-Inc/utopia)
[![CocoaPods](https://img.shields.io/cocoapods/v/ExpysSDK.svg)](https://cocoapods.org/pods/ExpysSDK)
-->

Official Expys data SDK for Swift. SwiftPM, async/await, URLSession, **zero
runtime dependencies** (Foundation only). Built in the Swift 6 language mode with
complete data-race checking.

> The source lives in the Expys monorepo (`packages/sdk-swift`). Releases are
> mirrored to the public `expys-swift` repo so SwiftPM can resolve them by git
> URL + semver tag. Add the package from the mirror, not this path.

> Beta. The generated models and transport are stable to use; the ergonomic layer
> is hardening during the rollout window. Pin an exact version in production and
> review the [versioning policy](https://docs.expys.com/guides/versioning).

## Getting Started

### Install

#### Swift Package Manager (primary)

In `Package.swift`:

```swift
.package(url: "https://github.com/Utopia-Members-Club-Inc/expys-swift.git", from: "0.1.0")
```

Or in Xcode: File -> Add Package Dependencies -> the `expys-swift` URL.

#### CocoaPods

```ruby
pod 'ExpysSDK', '~> 0.1'
```

### Quick start

```swift
import ExpysSDK

let client = ExpysClient(
  configuration: ExpysConfiguration(
    // A short-lived member token your backend obtained from POST /v1/auth/exchange.
    token: memberToken,
    environment: .live  // or .sandbox
  )
)

let offers = try await client.listOffers(limit: 20)
let redemption = try await client.createRedemption(.init(offer: offers.data[0].id))
let status = try await client.getRedemption(id: redemption.id)
let eligibility = try await client.eligibility()
let wallet = try await client.wallet()
```

## Authentication & Token Refresh

The SDK holds a **short-lived member token**, never the Org-API-Key. Your backend
exchanges its secret Org-API-Key for a member token (`POST /v1/auth/exchange`,
server-to-server) and hands it to the app. The SDK attaches it as a Bearer token
and, if you provide `refreshToken`, refreshes it automatically near expiry and on
a `401`.

`refreshToken` must call **your** backend and return a
`TokenRefresh(accessToken:expiresAt:)`:

```swift
let client = ExpysClient(
  configuration: ExpysConfiguration(
    token: memberToken,
    tokenExpiresAt: Date().addingTimeInterval(5 * 60),
    refreshToken: {
      // Call YOUR backend, which re-exchanges the Org-API-Key. Decode its
      // response and return a fresh token (TokenRefresh is constructed, not
      // decoded, so your backend's payload shape stays your concern).
      var request = URLRequest(url: refreshURL)
      request.httpMethod = "POST"
      let (data, _) = try await URLSession.shared.data(for: request)
      let body = try JSONDecoder().decode(MyRefreshResponse.self, from: data)
      return TokenRefresh(accessToken: body.accessToken, expiresAt: body.expiresAt)
    },
    refreshSkew: 60  // refresh ~60s before expiry
  )
)
```

- Called **proactively** within `refreshSkew` (default 30s) of `tokenExpiresAt`,
  and **reactively** once on a `401`.
- If it throws, the error propagates to your call -- the SDK does **not** retry a
  hard-failed refresh. Without `refreshToken`, an expired token simply `401`s.

See [`Examples/TokenRefresh`](Examples/TokenRefresh/TokenRefresh.swift).

## Environments

`environment` (`.live` / `.sandbox`, default `.live`) is **informational**: it is
enforced server-side by the token claim, so the SDK does not route by it (it only
surfaces it in the `User-Agent`). Use a sandbox token to hit sandbox.

## Offers

`listOffers` is cursor-paginated; follow `nextCursor` until it is nil:

```swift
var cursor: String?
repeat {
  let page = try await client.listOffers(limit: 50, cursor: cursor)
  // handle page.data
  cursor = page.nextCursor
} while cursor != nil
```

## Redemptions

```swift
let redemption = try await client.createRedemption(.init(offer: offerID))
let status = try await client.getRedemption(id: redemption.id)

// Cursor-paginated history, filtered by lifecycle status.
let page = try await client.listRedemptions(status: "OPEN", limit: 50)
```

Writes send an `Idempotency-Key` automatically so a retry replays the original
response rather than double-booking. Override it (e.g. to make a write retry-safe
across process restarts) by pre-generating a key:

```swift
let key = generateIdempotencyKey()  // persist this, then reuse it on retry
_ = try await client.createRedemption(.init(offer: offerID), idempotencyKey: key)
```

`createRedemption` surfaces the typed failure modes by status + stable `code`: a
`409` is `ExpysError.api` with `kind == .conflict` (code
`REDEMPTION_ALREADY_EXISTS`) when the member already booked the offer, and a `422`
is `ExpysError.api` with `code == "INSUFFICIENT_POINTS"` when the wallet balance is
too low (see [Errors](#errors)).

`listRedemptions` is cursor-paginated and filters by lifecycle `status`
(`SUBMITTED`, `OPEN`, `AWAITING_VENDOR`, `AWAITING_CUSTOMER`, `PURCHASED`,
`CANCELED`, `COMPLETED`). `externalUserID` names the member when a machine token
reads on their behalf.

## Eligibility

```swift
// externalUserID names the member when a machine token calls on their behalf.
let eligibility = try await client.eligibility(externalUserID: nil)
print(eligibility.tier, eligibility.wallet.balance)
```

## Wallet

```swift
let wallet = try await client.wallet()
print(wallet.balance, wallet.amountReceived, wallet.amountSpent, wallet.currency.symbol)

// The cursor-paginated points ledger (each credit/debit).
let ledger = try await client.walletTransactions(limit: 50)
```

`walletTransactions` accepts an optional `externalUserID` (a machine token reading
on a member's behalf).

## Conversations

```swift
let conversations = try await client.listConversations(externalUserID: nil)
let id = conversations.conversations[0].id

// Cursor-paginated messages in a conversation.
let messages = try await client.listMessages(id: id, limit: 50)

// A member-only write; it auto-sends an Idempotency-Key (override it per call).
let result = try await client.sendMessage(id: id, message: "Hello")
print(result.ok)
```

`listConversations` and `listMessages` accept an optional `externalUserID` (a
machine token acting on a member's behalf). `sendMessage` is member-only and takes
no `externalUserID`.

### Streaming

`streamMessages(id:)` returns an `AsyncThrowingStream<Message, Error>` of new,
member-visible messages over Server-Sent Events. Consume it with `for try await`;
history is not replayed (pair it with `listMessages` for the backlog). The stream
reconnects with backoff on transient failures (network drop / `5xx` / `429`,
honoring `Retry-After`) and refreshes once on a `401`; it finishes by throwing an
`ExpysError.api` on a permanent error (`kind == .forbidden` / `.notFound`, or
`.unauthorized` after a failed refresh). Member-only - it takes no `externalUserID`.

```swift
for try await message in client.streamMessages(id: "cnv_123") {
  print(message.body ?? "")
}
```

Cancelling the consuming `Task` tears down the underlying connection and any
pending reconnect timer. This is the one intentional concurrency difference across
the SDKs (TypeScript returns an `AsyncIterable`, Kotlin a `Flow`); see the
`StreamMessages` example and [SDK differences](https://docs.expys.com/sdks/differences).

## Server vs app methods (server-only)

Most methods above run with a short-lived **member token** and are safe to call
from your app. The following methods are **server-only**: they require an
**Org-API-Key** machine credential (`expys_live_...` / `expys_sandbox_...`) and
**must run only on your backend** (a Swift service, a Vapor app, a CLI tool).
Never ship an Org-API-Key in an iOS/macOS app or any client.

| Method                                                       | Endpoint                          |
| ------------------------------------------------------------ | --------------------------------- |
| `client.exchangeToken(_:idempotencyKey:)`                    | `POST /v1/auth/exchange`          |
| `client.creditPoints(_:idempotencyKey:)`                     | `POST /v1/wallet/credit`          |
| `client.setMember(externalUserID:_:)`                        | `PUT /v1/members/{externalUserID}`    |
| `client.getMember(externalUserID:)`                          | `GET /v1/members/{externalUserID}`    |
| `client.removeMember(externalUserID:retainBalance:)`         | `DELETE /v1/members/{externalUserID}` |
| `client.analyticsSummary()`                                  | `GET /v1/analytics/summary`       |
| `client.analyticsOffers()`                                   | `GET /v1/analytics/offers`        |
| `client.analyticsTimeseries(from:to:interval:)`              | `GET /v1/analytics/timeseries`    |
| `client.createWebhook(_:idempotencyKey:)`                    | `POST /v1/webhooks`               |
| `client.listWebhooks()`                                      | `GET /v1/webhooks`                |
| `client.deleteWebhook(id:)`                                  | `DELETE /v1/webhooks/{id}`        |

If you configure the SDK with a member token (a `v4.local.…` PASETO) and call any
of these, the SDK **fails fast client-side** with `ExpysError.notConfigured`
**before any network request** — the credential is classified as a machine
credential iff it starts with `expys_`. The server **also** enforces this: a member
token is `403`'d via the route auth matrix. The three POSTs (`exchangeToken`,
`creditPoints`, `createWebhook`) auto-send an `Idempotency-Key` like the other
writes; the `PUT` and `DELETE`s are idempotent by HTTP semantics and send no key.

```swift
// Backend only — never in a client app.
let client = ExpysClient(configuration: ExpysConfiguration(token: orgApiKey, environment: .live))
let grant = try await client.exchangeToken(TokenExchangeRequest(externalUserID: "user_42"))
_ = try await client.creditPoints(CreditWalletRequest(amount: 100, externalUserID: "user_42"))
```

See the `ServerMode` example.

## Errors

Calls throw `ExpysError`:

```swift
do {
  _ = try await client.createRedemption(.init(offer: offerID))
} catch ExpysError.api(let error) {
  switch error.kind {
  case .conflict where error.code == "REDEMPTION_ALREADY_EXISTS":
    break  // already booked
  case .rateLimited:
    break  // error.retryAfterMs is set
  default:
    break
  }
} catch ExpysError.timeout {
  // request timed out
}
```

`ExpysError` cases: `.api(APIError)`, `.network(String)`, `.timeout`,
`.decoding(String)`, `.notConfigured(String)`. `APIError` carries `status`,
`code` (the stable envelope code), `message`, optional `retryAfterMs`
(milliseconds, matching the TS/Kotlin SDKs), optional `requestId` (the server's
`x-request-id` -- quote it to support to trace the call), and a coarse `kind`.

`code` is the stable contract -- switch on it (e.g. `REDEMPTION_ALREADY_EXISTS` on
a 409, `INSUFFICIENT_POINTS` on a 422 when the wallet balance is too low), but
treat an unknown code as the generic class for its `kind` (new codes can appear
without a major version). The full list lives in the
[`/v1` error responses](https://docs.expys.com/guides/errors).

## Retries & Timeouts

`429`/`5xx` responses are retried with full-jitter exponential backoff (base
500ms, cap 10s) honoring `Retry-After` (clamped to [0, 300s]). Defaults:
`maxRetries` is **2** (3 attempts total); `timeout` is unset -- set
`ExpysConfiguration.timeout` (seconds) for a per-request ceiling. Task
cancellation always propagates and is never retried.

## Configuration Reference

| Option            | Type                  | Default        | Notes                                            |
| ----------------- | --------------------- | -------------- | ------------------------------------------------ |
| `token`           | `String`              | (required)     | Short-lived member token from your backend.      |
| `environment`     | `ExpysEnvironment`    | `.live`        | `.live` / `.sandbox`; informational only.        |
| `baseURL`         | `URL`                 | default host   | API host (sandbox and live share one).           |
| `orgID`           | `String?`             | `nil`          | Folded into the `User-Agent` for attribution.    |
| `tokenExpiresAt`  | `Date?`               | `nil`          | Enables proactive refresh.                        |
| `refreshToken`    | `(@Sendable) async throws -> TokenRefresh)?` | `nil` | Calls your backend for a fresh token. |
| `maxRetries`      | `Int`                 | `2`            | Extra attempts on 429/5xx.                       |
| `timeout`         | `TimeInterval?`       | `nil`          | Per-request ceiling, in seconds.                 |
| `refreshSkew`     | `TimeInterval`        | `30`           | Refresh this long before expiry.                 |
| `userAgentSuffix` | `String?`             | `nil`          | Appended to the SDK `User-Agent`.                |

The `httpClient` initializer parameter injects a custom `HTTPRequesting` (for
instrumentation, metrics, or a custom transport); it defaults to `URLSession`.

## Versioning Policy

SDK versioning is independent semver, decoupled from the spec version, and follows
the [Expys SDK versioning and deprecation policy](https://docs.expys.com/guides/versioning).
See the [CHANGELOG](CHANGELOG.md).

## Documentation

The full API reference is a [DocC](https://www.swift.org/documentation/docc/)
catalog (`Sources/ExpysSDK/ExpysSDK.docc`), hosted on the
[Swift Package Index](https://swiftpackageindex.com/Utopia-Members-Club-Inc/expys-swift/documentation/expyssdk)
once the mirror is registered. Build it locally with:

```sh
EXPYS_BUILD_DOCS=1 swift package --disable-sandbox \
  generate-documentation --target ExpysSDK
```

## Examples

Runnable, env-var-driven samples (zero UI) live in [`Examples/`](Examples), one
per concept, mirroring the TypeScript and Kotlin SDKs:
`BrowseRedeem`, `Pagination`, `ErrorHandling`, `TokenRefresh`, `Environments`,
`Idempotency`, `Configuration`, `EligibilityWallet`, `RedemptionsList`,
`Conversations`. Run one with, e.g.:

```sh
EXPYS_MEMBER_TOKEN=<token> swift run PaginationExample
```

## Platform support

iOS 15+ and macOS 12+ (async/await). Linux (Swift 6.1) is supported for
server-side use and CI. Requires the Swift 6 toolchain.

## Other SDKs

The TypeScript and Kotlin SDKs expose the same methods and behavior. See
[SDK differences](https://docs.expys.com/sdks/differences) for the intentional per-language
differences (and what's guaranteed identical).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build/test/lint/docs commands, the
`swift/vX.Y.Z` release + mirror flow, and the cross-SDK parity rule.

## Security

Report vulnerabilities privately -- see [SECURITY.md](SECURITY.md). Please do not
open a public issue. The SDK sends no telemetry.
