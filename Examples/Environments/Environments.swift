// Environments: sandbox vs live. The environment is enforced server-side by the
// token claim - the SDK does not route by it, it only surfaces it in the
// User-Agent. Point at sandbox by exchanging a sandbox Org-API-Key on your
// backend. Zero UI.
//
// Run: EXPYS_ENV=sandbox EXPYS_MEMBER_TOKEN=... swift run EnvironmentsExample
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

@main
struct EnvironmentsExample {
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["EXPYS_MEMBER_TOKEN"] else {
      fatalError("Set EXPYS_MEMBER_TOKEN (a member token from your backend's /v1/auth/exchange)")
    }
    let baseURL =
      environment["EXPYS_BASE_URL"].flatMap(URL.init(string:))
      ?? ExpysConfiguration.defaultBaseURL

    // Default to sandbox for safe experimentation; pass EXPYS_ENV=live to go live.
    let selected: ExpysEnvironment = environment["EXPYS_ENV"] == "live" ? .live : .sandbox

    let client = ExpysClient(
      configuration: ExpysConfiguration(
        token: token,
        environment: selected,
        baseURL: baseURL,
        // orgID is optional and only surfaces in the User-Agent for attribution.
        orgID: environment["EXPYS_ORG_ID"],
        // Identify your app in the User-Agent alongside the SDK and environment.
        userAgentSuffix: "examples/environments"
      )
    )

    print("using the \(selected.rawValue) environment")
    let offers = try await client.listOffers(limit: 5)
    print("fetched \(offers.data.count) offers")
  }
}
