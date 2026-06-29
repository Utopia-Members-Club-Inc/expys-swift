// Idempotency: writes auto-send an Idempotency-Key so a retry replays rather than
// double-books. Pre-generate an explicit key to make a write retry-safe across
// process restarts (resume the same logical operation with the same key). Zero UI.
//
// Run: EXPYS_MEMBER_TOKEN=... swift run IdempotencyExample
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

@main
struct IdempotencyExample {
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
      configuration: ExpysConfiguration(token: token, environment: .sandbox, baseURL: baseURL)
    )

    // Generate the key once and persist it (e.g. with the operation record) so a
    // retry after a crash reuses it; the server replays the original response.
    let idempotencyKey = generateIdempotencyKey()
    print("idempotency key: \(idempotencyKey)")

    // The same key sent twice replays the first result rather than acting twice.
    for attempt in 1...2 {
      do {
        let redemption = try await client.createRedemption(
          .init(offer: offer),
          idempotencyKey: idempotencyKey
        )
        print("attempt \(attempt): redemption \(redemption.id) [\(redemption.status)]")
      } catch ExpysError.api(let error) where error.kind == .conflict {
        print("attempt \(attempt): conflict (\(error.code))")
      }
    }
  }
}
