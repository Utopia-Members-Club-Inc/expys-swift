# Changelog

All notable changes to the Expys Swift SDK (`ExpysSDK`) are documented here. This
project follows [Semantic Versioning](https://semver.org) and the
[Expys SDK versioning and deprecation policy](https://docs.expys.com/guides/versioning).

## 0.1.0 - 2026-06-29

### Changed (breaking — pre-1.0, beta)

- **`APIError.retryAfter` (seconds) → `retryAfterMs` (milliseconds)**, matching the
  TS and Kotlin SDKs so the rate-limit hint reads the same across platforms.
- **Platform support narrowed to iOS 15+ and macOS 12+** (was iOS/macOS/tvOS/
  watchOS/visionOS). The SDK is Foundation-only so it still builds on the other
  Apple platforms, but they are no longer declared or CI-verified; declared
  support now matches what CI tests.

### Added

- **Server-mode methods** (server-only, require an Org-API-Key machine credential):
  `exchangeToken`, `creditPoints`, `setMember`, `getMember`, `removeMember`,
  `analyticsSummary`, `analyticsOffers`, `analyticsTimeseries`, `createWebhook`,
  `listWebhooks`, and `deleteWebhook` (parity with the TS and Kotlin SDKs).
  Calling one with a member token throws `ExpysError.notConfigured` client-side
  before any request (the server also `403`s it). These add `PUT`/`DELETE`
  transport support.
- **Member-mode methods**: `listRedemptions`, `walletTransactions`,
  `listConversations`, `listMessages`, and `sendMessage` (parity with the TS and
  Kotlin SDKs).
- **`streamMessages(id:)`**: a member-mode SSE stream of new conversation messages,
  returning an `AsyncThrowingStream<Message, Error>` (TypeScript `AsyncIterable`,
  Kotlin `Flow`). It reconnects with backoff on transient failures, refreshes once
  on a `401`, and ends on a permanent error; cancelling the consuming `Task` tears
  down the connection.
- **New models** for the surface above: `Conversation`, `Message`, and the wallet
  `Transaction`, plus the member, analytics, and webhook types (`MemberSummary`,
  `SetMemberRequest`/`SetMemberResponse`, `CreditWalletRequest`/`CreditWalletResponse`,
  the `GetAnalytics*Response` shapes, `TokenExchangeRequest`/`TokenGrant`, and
  `CreateWebhookRequest`/`WebhookEndpoint`/`WebhookEndpointWithSecret`/
  `WebhookEndpointList`).
- **`Offer.pointsPrice`** — the points cost of a points-priced offer.
- **`APIError.requestId`** — the server's `x-request-id`, for support correlation.
- `environment` and `orgID` are now folded into the `User-Agent` for attribution.
- Coverage gate (≥90%) enforced in CI (now 94%).
- **`generateIdempotencyKey()` is now public**, matching the TypeScript SDK, so you
  can pre-generate a write key and reuse it across retries/process restarts.
- **visionOS support** (visionOS 1+) is now declared and tested.

### Changed

- **Adopted the Swift 6 language mode** (`swift-tools-version:6.0`) with complete
  data-race checking; the package builds clean with `-strict-concurrency=complete`.
  The Swift 5.9-toolchain CI leg is dropped (the 6.0 manifest needs Swift 6); the
  OS deployment floors (iOS 15 / macOS 12 / tvOS 15 / watchOS 8) are unchanged.
- The transport request engine was refactored into small, single-purpose helpers
  (behavior unchanged; covered by the full test suite).

### Tooling, docs, and distribution

- **DocC catalog** (`Sources/ExpysSDK/ExpysSDK.docc`) with topic groups, a `///`
  doc comment on every public symbol, and a CI documentation build (warnings as
  errors). `.spi.yml` lets the Swift Package Index host the docs and render the
  platform/Swift-version badges.
- **SwiftLint** (`.swiftlint.yml`) and **swift-format** (`.swift-format`), both run
  strict (warnings as errors) locally and in CI.
- **CocoaPods** support via `ExpysSDK.podspec` (validated with `pod lib lint`).
- **CI on real Apple platforms** — a macOS `xcodebuild` matrix (iOS, macOS, tvOS,
  watchOS, visionOS, across the current and previous Xcode), alongside the Linux
  `swift` matrix; plus Codecov upload (flag `sdk-swift`).
- **Tests migrated to Swift Testing**, with added edge-case coverage and an opt-in
  sandbox integration suite (`EXPYS_INTEGRATION=1`).
- Full example set under `Examples/` (one per concept, mirroring the TS/Kotlin
  SDKs): `Pagination`, `ErrorHandling`, `TokenRefresh`, `Environments`,
  `Idempotency`, `Configuration`, `EligibilityWallet` (plus `BrowseRedeem`).
- Package `CONTRIBUTING.md` and `SECURITY.md`; README expanded to the shared
  docs-site taxonomy with a real badge row.
