// Balance: read your org's points balance, credit limit, and settlement mode.
//
// RUN THIS IN A SERVER/BACKEND CONTEXT ONLY. Reading the balance needs an
// Org-API-Key (`expys_live_...` / `expys_sandbox_...`) with the BILLING_READ
// scope. That key is a secret and must NEVER ship in an iOS/macOS app or any
// client.
//
// Which layer your redemptions debit depends on `settlementMode`:
//  - memberWallet: each VIP has their own wallet, which you fund by crediting
//    points. Redemptions debit the VIP.
//  - orgPool: there are no per-VIP balances at all. Redemptions debit this
//    org-level balance directly, so you never mirror or reconcile a VIP balance.
//
// In orgPool mode no webhook fires per redemption, so poll this endpoint (or
// subscribe to `org.points.low`) to know when to top up.
//
// Run: EXPYS_ORG_API_KEY=expys_live_... swift run BalanceExample
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

@main
struct BalanceExample {
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

    let client = ExpysClient(
      configuration: ExpysConfiguration(token: orgApiKey, environment: .sandbox, baseURL: baseURL)
    )

    let account = try await client.balance()

    print("settlement mode: \(account.settlementMode.rawValue)")
    print("balance: \(account.balance) points")

    switch account.settlementMode {
    case .orgPool:
      // Spendable headroom includes the credit limit: a postpaid org may overdraw
      // to -creditLimit before redemptions are refused with INSUFFICIENT_ORG_POINTS.
      let spendable = account.balance + account.creditLimit
      print("spendable now: \(spendable) points")
      print("lifetime spent from the pool: \(account.lifetimeSpent)")

      if spendable <= 0 {
        print("Pool exhausted - redemptions will be refused until topped up.")
      }
    case .memberWallet:
      // memberWallet: this balance funds the points you credit to VIPs, and each
      // VIP's own wallet is what a redemption debits.
      print("VIP redemptions debit each member's wallet, not this balance.")
    }
  }
}
