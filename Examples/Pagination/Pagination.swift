// Pagination: walk the cursor to exhaustion. Zero UI.
//
// Run: EXPYS_MEMBER_TOKEN=... swift run PaginationExample
//
// EXPYS_MEMBER_TOKEN is a short-lived member token your backend obtained from
// POST /v1/auth/exchange. Point EXPYS_BASE_URL at a stub until the sandbox tenant
// is seeded.
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

@main
struct PaginationExample {
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

    var cursor: String?
    var page = 0
    var total = 0

    // Loop until the server returns a nil nextCursor, marking the end of the list.
    repeat {
      let result = try await client.listOffers(limit: 50, cursor: cursor)
      page += 1
      total += result.data.count
      print("page \(page): \(result.data.count) offers")
      cursor = result.nextCursor
    } while cursor != nil

    print("done: \(total) offers across \(page) page(s)")
  }
}
