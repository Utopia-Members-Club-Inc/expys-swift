// Conversations: list threads, read their messages, and send a message. Zero UI.
//
// Run: EXPYS_MEMBER_TOKEN=... swift run ConversationsExample
//
// EXPYS_MEMBER_TOKEN is a short-lived member token your backend obtained from
// POST /v1/auth/exchange. listConversations/listMessages accept an optional
// externalUserID (a machine token acting on a member's behalf); sendMessage is
// member-only and takes no externalUserID.
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

@main
struct ConversationsExample {
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

    let conversations = try await client.listConversations(externalUserID: externalUserID)
    print("found \(conversations.conversations.count) conversations")

    guard let conversation = conversations.conversations.first else { return }
    print("reading: \(conversation.title ?? conversation.id)")

    let messages = try await client.listMessages(
      id: conversation.id, limit: 50, externalUserID: externalUserID)
    for message in messages.messages {
      print("[\(message.authorID)] \(message.body ?? "(no body)")")
    }

    // Writes auto-send an Idempotency-Key so a retry replays rather than double-posts.
    let result = try await client.sendMessage(id: conversation.id, message: "Hello from the SDK")
    print("message sent: ok=\(result.ok)")
  }
}
