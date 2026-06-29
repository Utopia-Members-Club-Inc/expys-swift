import Foundation

/// A minimal Server-Sent Events parser, kept pure (a transform over a line
/// sequence) so the data-accumulation rules are testable without a network.
/// Implements only the slice of the SSE wire format the stream endpoint uses:
/// `data:` lines (accumulated, newline-joined) terminated by a blank line, with
/// comment lines (`:`-prefixed heartbeats) ignored. `event:`/`id:` and other
/// fields are accepted but unused.
///
/// Input is a sequence of already-split lines (e.g. `URLSession.bytes.lines`),
/// so CRLF/LF splitting is the byte layer's concern; this only strips a single
/// optional leading space after the field colon.
enum SSEParser {
  /// Accumulates SSE lines into completed-event `data` payloads. Returns the
  /// payload to yield for a completed event, or `nil` when the line did not
  /// terminate an event (a field line, comment, or a blank line with no data).
  struct State {
    private var dataLines: [String] = []
    private var sawData = false

    /// Feeds one line. Returns the joined `data` payload when this line (a blank
    /// line) terminates an event that carried data; otherwise `nil`.
    mutating func consume(line: String) -> String? {
      if line.isEmpty {
        return flush()
      }
      if line.hasPrefix(":") {
        return nil  // comment / heartbeat
      }
      let (field, value) = Self.split(line)
      if field == "data" {
        sawData = true
        dataLines.append(value)
      }
      return nil
    }

    /// Emits a pending event with no trailing blank line (end of stream).
    mutating func flush() -> String? {
      guard sawData else {
        dataLines = []
        return nil
      }
      let payload = dataLines.joined(separator: "\n")
      dataLines = []
      sawData = false
      return payload
    }

    private static func split(_ line: String) -> (field: String, value: String) {
      guard let colon = line.firstIndex(of: ":") else {
        return (line, "")
      }
      let field = String(line[line.startIndex..<colon])
      var value = line[line.index(after: colon)...]
      if value.first == " " {
        value = value.dropFirst()  // strip exactly one leading space
      }
      return (field, String(value))
    }
  }

  /// Transforms an async line stream into the `data` payload of each completed
  /// SSE event. A non-blank trailing event is flushed when the source ends. The
  /// input is the concrete (Sendable) line stream the transport produces.
  static func events(
    from lines: AsyncThrowingStream<String, Error>
  ) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var state = State()
        do {
          for try await line in lines {
            if let payload = state.consume(line: line) {
              continuation.yield(payload)
            }
          }
          if let payload = state.flush() {
            continuation.yield(payload)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
