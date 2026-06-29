// Redemptions history and wallet ledger: the member-facing list read paths. Zero UI.
//
// Run: EXPYS_MEMBER_TOKEN=... swift run RedemptionsListExample
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
struct RedemptionsListExample {
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["EXPYS_MEMBER_TOKEN"] else {
      fatalError("Set EXPYS_MEMBER_TOKEN (a member token from your backend's /v1/auth/exchange)")
    }
    let baseURL =
      environment["EXPYS_BASE_URL"].flatMap(URL.init(string:))
      ?? ExpysConfiguration.defaultBaseURL
    let externalUserID = environment["EXPYS_EXTERNAL_USER_ID"]

    let client = ExpysClient(
      configuration: ExpysConfiguration(token: token, environment: .sandbox, baseURL: baseURL)
    )

    // Cursor-paginate the member's open redemptions until nextCursor is nil.
    var cursor: String?
    repeat {
      let page = try await client.listRedemptions(
        status: "OPEN", limit: 50, cursor: cursor, externalUserID: externalUserID)
      for redemption in page.redemptions {
        print("redemption \(redemption.id) [\(redemption.status)]")
      }
      cursor = page.nextCursor
    } while cursor != nil

    // The points ledger: each credit/debit on the member's wallet.
    let ledger = try await client.walletTransactions(limit: 50, externalUserID: externalUserID)
    for transaction in ledger.transactions {
      print(
        "tx \(transaction.id): \(transaction.type) \(transaction.amount) "
          + "(\(transaction.reason ?? "no reason"))")
    }
  }
}
