// Reference sample: data-only browse -> eligibility -> redemption flow. Zero UI.
//
// CROSS-PHASE DEPENDENCY: this completes end-to-end against the seeded sandbox
// tenant from Phase 4.6 (not yet built). Until then, point EXPYS_BASE_URL at a
// stub. EXPYS_MEMBER_TOKEN is a short-lived member token your backend obtained
// from POST /v1/auth/exchange.
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

@main
struct BrowseRedeem {
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

    let eligibility = try await client.eligibility()
    print("tier: \(eligibility.tier), balance: \(eligibility.wallet.balance)")

    let offers = try await client.listOffers(limit: 10)
    print("browsed \(offers.data.count) offers")

    guard let offer = offers.data.first else { return }
    print("redeeming: \(offer.title) (\(offer.id))")

    do {
      let redemption = try await client.createRedemption(.init(offer: offer.id))
      print("redemption created: \(redemption.id) [\(redemption.status)]")
      let status = try await client.getRedemption(id: redemption.id)
      print("status now: \(status.status)")
    } catch ExpysError.api(let error) where error.code == "REDEMPTION_ALREADY_EXISTS" {
      print("already redeemed")
    }
  }
}
