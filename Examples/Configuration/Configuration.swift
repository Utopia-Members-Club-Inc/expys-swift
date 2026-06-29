// Configuration: timeouts, retry budget, and a custom HTTP layer (for
// instrumentation or a custom transport). Zero UI.
//
// Run: EXPYS_MEMBER_TOKEN=... swift run ConfigurationExample
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A custom HTTP layer that logs each request, then delegates to URLSession. Use
/// this seam (the `httpClient` injection point) for tracing, metrics, or a custom
/// transport - the Swift analogue of the TS example's instrumented `fetch`.
struct InstrumentedHTTP: HTTPRequesting {
  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    print("-> \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
    return try await URLSession.shared.data(for: request)
  }
}

@main
struct ConfigurationExample {
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["EXPYS_MEMBER_TOKEN"] else {
      fatalError("Set EXPYS_MEMBER_TOKEN (a member token from your backend's /v1/auth/exchange)")
    }
    let baseURL =
      environment["EXPYS_BASE_URL"].flatMap(URL.init(string:))
      ?? ExpysConfiguration.defaultBaseURL

    let client = ExpysClient(
      configuration: ExpysConfiguration(
        token: token,
        environment: .sandbox,
        baseURL: baseURL,
        // Retry 429/5xx up to 3 extra times (4 attempts total) with backoff.
        maxRetries: 3,
        // Abort any single attempt that exceeds 8s.
        timeout: 8
      ),
      httpClient: InstrumentedHTTP()
    )

    let offers = try await client.listOffers(limit: 3)
    print("fetched \(offers.data.count) offers with the configured client")
  }
}
