// Streaming: subscribe to new conversation messages over SSE, with cancellation.
// Zero UI.
//
// Run: EXPYS_MEMBER_TOKEN=... EXPYS_CONVERSATION_ID=... swift run StreamMessagesExample
//
// EXPYS_MEMBER_TOKEN is a short-lived member token your backend obtained from
// POST /v1/auth/exchange. streamMessages is member-only (no externalUserID) and
// pushes only NEW messages; use listMessages for the backlog. The stream
// reconnects with backoff on transient failures and ends on a permanent error.
//
// This file ships in the public expys-swift mirror under Examples/ as an
// executable target; it is not part of the ExpysSDK library target.
import ExpysSDK
import Foundation

@main
struct StreamMessagesExample {
  static func main() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let token = environment["EXPYS_MEMBER_TOKEN"] else {
      fatalError("Set EXPYS_MEMBER_TOKEN (a member token from your backend's /v1/auth/exchange)")
    }
    guard let conversationID = environment["EXPYS_CONVERSATION_ID"] else {
      fatalError("Set EXPYS_CONVERSATION_ID (a conversation to stream)")
    }
    let baseURL =
      environment["EXPYS_BASE_URL"].flatMap(URL.init(string:))
      ?? ExpysConfiguration.defaultBaseURL

    let client = ExpysClient(
      configuration: ExpysConfiguration(token: token, environment: .sandbox, baseURL: baseURL)
    )

    // Optional: print the recent backlog first, then live-stream what follows.
    let history = try await client.listMessages(id: conversationID, limit: 20)
    for message in history.messages {
      print("[history \(message.authorID)] \(message.body ?? "(no body)")")
    }

    print("listening for new messages (stops after 5)...")

    // Drive the stream from a Task so cancellation tears down the connection.
    // `for try await` consumes the AsyncThrowingStream lazily; breaking the loop
    // (here, after five messages) cancels the consuming Task, which severs the
    // underlying connection and any pending reconnect timer - no leaked sockets.
    let task = Task {
      var received = 0
      for try await message in client.streamMessages(id: conversationID) {
        received += 1
        print("[live \(message.authorID)] \(message.body ?? "(no body)")")
        if received >= 5 {
          break  // closes the connection
        }
      }
      return received
    }

    let received = try await task.value
    print("done: received \(received) live message(s)")
  }
}
