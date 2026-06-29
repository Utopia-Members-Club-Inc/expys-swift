// See Configuration.swift: `@preconcurrency` silences cross-module Sendable
// warnings for Foundation's `URL` on the Swift 6.0/6.1 CI toolchains (a no-op on
// newer ones). The streaming transport stores a `URL` and conforms to `Sendable`.
@preconcurrency import Foundation

#if canImport(FoundationNetworking)
  @preconcurrency import FoundationNetworking
#endif

/// A streaming HTTP response: the status, headers, and a lazy line stream. The
/// body is delivered as already-split UTF-8 lines (the SSE byte framing is the
/// transport's concern), and cancelling the consuming task tears down the
/// underlying connection.
struct StreamingResponse: Sendable {
  let status: Int
  let headers: [String: String]
  let lines: AsyncThrowingStream<String, Error>
}

/// Streaming sibling of ``HTTPRequesting``: opens a connection and exposes the
/// body as a line stream rather than a buffered `Data`. Injectable so the
/// streaming engine is testable with a scripted stub.
protocol StreamingHTTPRequesting: Sendable {
  func stream(for request: URLRequest) async throws -> StreamingResponse
}

/// Default streaming HTTP layer backed by `URLSession.bytes(for:)`. Available on
/// Apple platforms; the streaming method is unsupported on Linux Foundation
/// (which lacks `URLSession.bytes`), where `streamMessages` is not offered.
struct URLSessionStreamingHTTP: StreamingHTTPRequesting {
  func stream(for request: URLRequest) async throws -> StreamingResponse {
    #if canImport(FoundationNetworking)
      throw ExpysError.network("Streaming is not supported on this platform")
    #else
      let (bytes, response) = try await URLSession.shared.bytes(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw ExpysError.network("Non-HTTP response")
      }
      return StreamingResponse(
        status: http.statusCode,
        headers: headerDictionary(from: http.allHeaderFields),
        lines: linesStream(from: bytes.lines)
      )
    #endif
  }
}

/// Normalizes `HTTPURLResponse.allHeaderFields` (an `[AnyHashable: Any]`) into a
/// `[String: String]`, dropping any non-string entries. Pure, so it is unit-
/// tested independently of a live `URLSession`.
func headerDictionary(from raw: [AnyHashable: Any]) -> [String: String] {
  var headers: [String: String] = [:]
  for (key, value) in raw {
    if let key = key as? String, let value = value as? String {
      headers[key] = value
    }
  }
  return headers
}

/// Wraps any async line sequence in a cancellable `AsyncThrowingStream`, so the
/// consumer terminating (breaking / cancelling) cancels the producing task and
/// severs the underlying connection. Generic over the source so it is testable
/// with an in-memory sequence rather than `URLSession.bytes`.
func linesStream<Source: AsyncSequence & Sendable>(
  from source: Source
) -> AsyncThrowingStream<String, Error> where Source.Element == String {
  AsyncThrowingStream { continuation in
    let task = Task {
      do {
        for try await line in source {
          continuation.yield(line)
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    continuation.onTermination = { _ in task.cancel() }
  }
}

/// The streaming engine: connects to an SSE endpoint, decodes each event into a
/// model, reconnects with full-jitter backoff on transient failures (network
/// drop / 5xx / 429, honoring Retry-After), refreshes once on a 401, and
/// terminates on a permanent 403/404. Mirrors ``Transport``'s policy; time and
/// randomness are injectable for testing.
struct StreamTransport: Sendable {
  let baseURL: URL
  let session: ExpysSession
  let http: StreamingHTTPRequesting
  let userAgent: String
  let timeout: TimeInterval?
  let sleep: @Sendable (TimeInterval) async throws -> Void
  let now: @Sendable () -> Date
  let random: @Sendable () -> Double

  /// Streams decoded models from `path` as an `AsyncThrowingStream`. The stream
  /// reconnects while the consumer is subscribed and finishes (throwing) on a
  /// permanent error; cancelling the consuming task tears down the connection.
  func stream<T: Decodable & Sendable>(path: String) -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await run(path: path) { (model: T) in
            continuation.yield(model)
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// What the loop should do after inspecting a connection's status: either
  /// `continueImmediately` (auth recovery, no sleep) or `backoff` then reconnect.
  private enum Outcome: Equatable {
    case continueImmediately
    case backoff
  }

  /// The reconnect loop. Calls `emit` for each decoded model; returns when
  /// cancelled, throws on a permanent error.
  private func run<T: Decodable & Sendable>(
    path: String,
    emit: @Sendable (T) -> Void
  ) async throws {
    let url = try buildURL(path: path)
    var attempt = 0
    var refreshedOn401 = false

    while !Task.isCancelled {
      try await refreshProactivelyIfNeeded()
      let request = buildRequest(url: url, token: await session.currentToken())

      let response: StreamingResponse
      do {
        response = try await http.stream(for: request)
      } catch {
        if isCancellation(error) { throw error }
        try await sleep(backoffDelay(attempt: attempt, random: random))  // transient
        attempt += 1
        continue
      }

      if !(200..<300).contains(response.status) {
        let outcome = try await handleErrorStatus(
          response, attempt: attempt, refreshedOn401: &refreshedOn401)
        // `.backoff` already slept inside; `.continueImmediately` is auth recovery.
        if outcome == .backoff { attempt += 1 }
        continue
      }

      // A successful connection resets the backoff sequence and the 401 budget.
      attempt = 0
      refreshedOn401 = false
      for try await payload in SSEParser.events(from: response.lines) {
        try Task.checkCancellation()
        emit(try decode(payload))
      }

      // The stream ended. If the consumer cancelled (broke iteration), stop here
      // rather than reconnecting; otherwise the server closed cleanly, so back
      // off and reconnect.
      try Task.checkCancellation()
      try await sleep(backoffDelay(attempt: attempt, random: random))
      attempt += 1
    }
  }

  /// Applies the error-status policy: throw on a permanent 403/404 (or a
  /// non-retryable status), refresh once on a 401 then reconnect immediately, or
  /// sleep the retry delay for a 429/5xx. Throws the typed API error to terminate.
  private func handleErrorStatus(
    _ response: StreamingResponse,
    attempt: Int,
    refreshedOn401: inout Bool
  ) async throws -> Outcome {
    let status = response.status
    let requestId = headerValue(response.headers, "x-request-id")

    if isRetryableStatus(status) {
      // Transient: don't pay to read the body (it isn't surfaced on a retry),
      // just back off. The line stream is finished by the stub/engine already.
      try await sleep(retryDelay(status: status, headers: response.headers, attempt: attempt))
      return .backoff
    }

    // Permanent error: read the small error body so the typed error carries the
    // server's stable envelope code/message, matching the buffered Transport.
    let data = await readErrorBody(response.lines)
    let apiError = mapAPIError(
      status: status, data: data, retryAfterMs: nil, requestId: requestId)

    if status == 401, session.canRefresh, !refreshedOn401 {
      refreshedOn401 = true
      do {
        try await session.refreshToken()
      } catch {
        if isCancellation(error) { throw error }
        throw apiError
      }
      return .continueImmediately
    }

    throw apiError
  }

  /// Drains the error response's line stream (a small JSON envelope) and rejoins
  /// it with newlines into the raw body bytes. The SSE byte layer split the body
  /// on newlines, so joining reconstructs the original JSON. A drain failure must
  /// not mask the API error, so it falls back to empty data and lets ``mapAPIError``
  /// use the status-derived defaults.
  private func readErrorBody(_ lines: AsyncThrowingStream<String, Error>) async -> Data {
    var collected: [String] = []
    do {
      for try await line in lines {
        collected.append(line)
      }
    } catch {
      return Data()
    }
    return Data(collected.joined(separator: "\n").utf8)
  }

  private func refreshProactivelyIfNeeded() async throws {
    guard await session.shouldRefreshProactively() else { return }
    do {
      try await session.refreshToken()
    } catch {
      if isCancellation(error) { throw error }
    }
  }

  private func retryDelay(
    status: Int, headers: [String: String], attempt: Int
  ) -> TimeInterval {
    let retryAfter = parseRetryAfter(headerValue(headers, "Retry-After"), now: now())
    if status == 429, let retryAfter {
      return retryAfter
    }
    return backoffDelay(attempt: attempt, random: random)
  }

  /// Case-insensitive header lookup. The streaming `headers` is a plain
  /// `[String: String]` (HTTP header names are case-insensitive), so a direct
  /// subscript could miss e.g. a lowercased `retry-after`. Mirrors the buffered
  /// ``Transport``, which reads headers via the case-insensitive
  /// `HTTPURLResponse.value(forHTTPHeaderField:)`.
  private func headerValue(_ headers: [String: String], _ name: String) -> String? {
    let lowered = name.lowercased()
    return headers.first { $0.key.lowercased() == lowered }?.value
  }

  private func decode<T: Decodable>(_ payload: String) throws -> T {
    do {
      return try JSONDecoder().decode(T.self, from: Data(payload.utf8))
    } catch {
      throw ExpysError.decoding(String(describing: error))
    }
  }

  private func buildURL(path: String) throws -> URL {
    guard let url = URL(string: baseURL.absoluteString + path) else {
      throw ExpysError.network("Invalid URL for path \(path)")
    }
    return url
  }

  private func buildRequest(url: URL, token: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    if let timeout {
      request.timeoutInterval = timeout
    }
    return request
  }

  private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    return (error as? URLError)?.code == .cancelled
  }
}
