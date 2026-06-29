// Server-mode: backend-only methods that require an Org-API-Key (machine
// credential), e.g. minting member tokens, crediting points, upserting members,
// and managing webhooks. Zero UI.
//
// RUN THIS IN A SERVER/BACKEND CONTEXT ONLY (a Swift service, a Vapor app, a
// command-line tool). The Org-API-Key (`expys_live_...` / `expys_sandbox_...`) is
// a secret and must NEVER ship in an iOS/macOS app or any client. If you
// configure the SDK with a member token (a `v4.local.…` PASETO) and call a
// server-mode method, the SDK fails fast with ExpysError.notConfigured BEFORE any
// network call (and the server 403s it anyway).
//
// Run: EXPYS_ORG_API_KEY=expys_live_... swift run ServerModeExample
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

@main
struct ServerModeExample {
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let orgApiKey = environment["EXPYS_ORG_API_KEY"] else {
      fatalError(
        "Set EXPYS_ORG_API_KEY (your secret Org-API-Key, e.g. expys_live_...). "
          + "Run this on a backend only, never in a client app.")
    }
    let baseURL =
      environment["EXPYS_BASE_URL"].flatMap(URL.init(string:))
      ?? ExpysConfiguration.defaultBaseURL
    let externalUserID = environment["EXPYS_EXTERNAL_USER_ID"] ?? "user_42"

    // Configure the client with the machine credential as the token. Server-mode
    // methods are guarded against member tokens client-side.
    let client = ExpysClient(
      configuration: ExpysConfiguration(token: orgApiKey, environment: .sandbox, baseURL: baseURL)
    )

    // Mint a short-lived member token for your app to use (return this to the app,
    // never the Org-API-Key). Idempotent POST: a retry replays rather than re-mints.
    let grant = try await client.exchangeToken(TokenExchangeRequest(externalUserID: externalUserID))
    print("minted member token expiring at \(grant.expiresAt)")

    // Upsert the member's profile. PUT is idempotent by HTTP semantics (no key).
    let member = try await client.setMember(
      externalUserID: externalUserID,
      SetMemberRequest(displayName: "Ada Lovelace", tier: "gold"))
    print("member \(member.externalUserID) is now tier=\(member.tier)")

    // Credit points to the member's wallet. Idempotent POST sends an Idempotency-Key.
    let credited = try await client.creditPoints(
      CreditWalletRequest(amount: 100, externalUserID: externalUserID, reason: "welcome bonus"))
    print("new balance: \(credited.balance) \(credited.currency.symbol)")

    // Register a webhook. The signingSecret is shown ONLY on creation - store it now.
    let webhook = try await client.createWebhook(
      CreateWebhookRequest(
        events: ["redemption.created"], url: "https://example.com/expys/webhooks"))
    print("webhook \(webhook.id) secret: \(webhook.signingSecret)")

    // Org-wide analytics rollups.
    let summary = try await client.analyticsSummary()
    print("members: \(summary.memberCount), minted: \(summary.pointsMinted)")
  }
}
