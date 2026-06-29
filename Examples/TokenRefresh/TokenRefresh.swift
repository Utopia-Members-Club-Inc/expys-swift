// Token refresh: proactive (before expiry) and reactive (once on a 401). The hook
// must call YOUR backend, which re-exchanges the secret Org-API-Key. Zero UI.
//
// Run: EXPYS_MEMBER_TOKEN=... swift run TokenRefreshExample
//
// EXPYS_MEMBER_TOKEN is the initial short-lived member token from your backend's
// POST /v1/auth/exchange. EXPYS_REFRESH_URL is your backend's refresh endpoint.
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Shape your backend's refresh endpoint returns. Decoded here (not in the SDK)
/// so the SDK stays transport-agnostic about your token plumbing.
private struct RefreshResponse: Decodable {
  let accessToken: String
  let expiresInSeconds: Double?
}

@main
struct TokenRefreshExample {
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["EXPYS_MEMBER_TOKEN"] else {
      fatalError("Set EXPYS_MEMBER_TOKEN (a member token from your backend's /v1/auth/exchange)")
    }
    let baseURL =
      environment["EXPYS_BASE_URL"].flatMap(URL.init(string:))
      ?? ExpysConfiguration.defaultBaseURL
    let refreshURL =
      environment["EXPYS_REFRESH_URL"].flatMap(URL.init(string:))
      ?? URL(string: "https://example.com/api/expys/refresh")!

    let client = ExpysClient(
      configuration: ExpysConfiguration(
        token: token,
        environment: .live,
        baseURL: baseURL,
        // Setting tokenExpiresAt enables proactive refresh; omit it to rely solely
        // on reactive (401) refresh.
        tokenExpiresAt: Date().addingTimeInterval(5 * 60),
        // Calls your backend, which re-exchanges the Org-API-Key. A thrown refresh
        // propagates to your call as an ExpysError and is NOT retried.
        refreshToken: {
          var request = URLRequest(url: refreshURL)
          request.httpMethod = "POST"
          let (data, response) = try await URLSession.shared.data(for: request)
          guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
          else {
            throw ExpysError.network("refresh failed")
          }
          let body = try JSONDecoder().decode(RefreshResponse.self, from: data)
          // Returning expiresAt re-arms proactive refresh for the next call.
          return TokenRefresh(
            accessToken: body.accessToken,
            expiresAt: body.expiresInSeconds.map { Date().addingTimeInterval($0) }
          )
        },
        // Refresh ~60s before expiry.
        refreshSkew: 60
      )
    )

    // If the token is within the skew window, the SDK refreshes before this call;
    // on a 401 it refreshes once and retries with the new token.
    let wallet = try await client.wallet()
    print("wallet balance: \(wallet.balance)")
  }
}
