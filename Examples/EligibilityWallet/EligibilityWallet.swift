// Eligibility and wallet: the member-facing read paths. Zero UI.
//
// Run: EXPYS_MEMBER_TOKEN=... swift run EligibilityWalletExample
//
// EXPYS_MEMBER_TOKEN is a short-lived member token your backend obtained from
// POST /v1/auth/exchange. Set EXPYS_EXTERNAL_USER_ID when a machine token reads
// on a specific member's behalf.
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

@main
struct EligibilityWalletExample {
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["EXPYS_MEMBER_TOKEN"] else {
      fatalError("Set EXPYS_MEMBER_TOKEN (a member token from your backend's /v1/auth/exchange)")
    }
    let baseURL =
      environment["EXPYS_BASE_URL"].flatMap(URL.init(string:))
      ?? ExpysConfiguration.defaultBaseURL

    let client = ExpysClient(
      configuration: ExpysConfiguration(token: token, environment: .sandbox, baseURL: baseURL)
    )

    // externalUserID names the member when a machine token calls on their behalf.
    let eligibility = try await client.eligibility(
      externalUserID: environment["EXPYS_EXTERNAL_USER_ID"]
    )
    print("tier: \(eligibility.tier)")
    print("wallet (from eligibility): \(eligibility.wallet.balance)")

    let wallet = try await client.wallet()
    print(
      "wallet: balance=\(wallet.balance) received=\(wallet.amountReceived) "
        + "spent=\(wallet.amountSpent) \(wallet.currency.symbol) (\(wallet.currency.name))"
    )
  }
}
