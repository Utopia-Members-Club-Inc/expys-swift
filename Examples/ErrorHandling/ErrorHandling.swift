// Error handling: branch on the typed ExpysError cases and the stable `code`,
// and surface `requestId` for support. Zero UI.
//
// Run: EXPYS_MEMBER_TOKEN=... swift run ErrorHandlingExample
//
// EXPYS_MEMBER_TOKEN is a short-lived member token your backend obtained from
// POST /v1/auth/exchange.
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

@main
struct ErrorHandlingExample {
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["EXPYS_MEMBER_TOKEN"] else {
      fatalError("Set EXPYS_MEMBER_TOKEN (a member token from your backend's /v1/auth/exchange)")
    }
    let baseURL =
      environment["EXPYS_BASE_URL"].flatMap(URL.init(string:))
      ?? ExpysConfiguration.defaultBaseURL
    let offer = environment["EXPYS_OFFER_ID"] ?? "off_1"

    let client = ExpysClient(
      configuration: ExpysConfiguration(
        token: token,
        environment: .sandbox,
        baseURL: baseURL,
        // A short ceiling so the timeout branch is reachable on a slow network.
        timeout: 10
      )
    )

    do {
      _ = try await client.createRedemption(.init(offer: offer))
      print("redemption created")
    } catch ExpysError.api(let error) {
      // Switch on the coarse `kind`, then refine with the stable `code`.
      switch error.kind {
      case .conflict where error.code == "REDEMPTION_ALREADY_EXISTS":
        print("already redeemed by this member")
      case .validation:
        print("validation failed: \(error.code)")
      case .unauthorized:
        print("token rejected; re-exchange a fresh member token on your backend")
      case .rateLimited:
        print("rate limited; retry after \(error.retryAfterMs.map(String.init) ?? "?")ms")
      default:
        // Unknown code: handle as the generic class for its kind. Quote requestId.
        print("api error \(error.status) (\(error.code)) requestId=\(error.requestId ?? "n/a")")
      }
    } catch ExpysError.timeout {
      print("request timed out")
    } catch ExpysError.network(let message) {
      print("network failure; no response received: \(message)")
    }
  }
}
