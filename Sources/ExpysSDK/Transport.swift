// See Configuration.swift: `@preconcurrency` silences cross-module Sendable
// warnings for Foundation's `URL` on the Swift 6.0/6.1 CI toolchains (a no-op on
// newer ones). `Transport` stores a `URL` and conforms to `Sendable`.
@preconcurrency import Foundation

#if canImport(FoundationNetworking)
  @preconcurrency import FoundationNetworking
#endif

/// Abstraction over URLSession so the request engine is testable with a stub.
public protocol HTTPRequesting: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Default HTTP layer backed by URLSession. A wrapper (rather than conforming
/// URLSession directly) avoids the protocol-witness mismatch with URLSession's
/// `data(for:delegate:)` and works identically on Apple and Linux Foundation.
struct URLSessionHTTP: HTTPRequesting {
  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await URLSession.shared.data(for: request)
  }
}

/// The request engine: token attach, proactive + reactive (401) refresh,
/// retry/backoff on 429/5xx honoring Retry-After, idempotency-key passthrough,
/// timeout, and typed-error mapping. Time/randomness is injectable for testing.
struct Transport: Sendable {
  let baseURL: URL
  let session: ExpysSession
  let http: HTTPRequesting
  let maxRetries: Int
  let userAgent: String
  let timeout: TimeInterval?
  let sleep: @Sendable (TimeInterval) async throws -> Void
  let now: @Sendable () -> Date
  let random: @Sendable () -> Double

  func request<T: Decodable>(
    method: String,
    path: String,
    query: [String: String?] = [:],
    body: Data? = nil,
    idempotencyKey: String? = nil
  ) async throws -> T {
    try await refreshProactivelyIfNeeded()

    let url = try buildURL(path: path, query: query)
    var attempt = 0
    var refreshedOn401 = false

    while true {
      let token = await session.currentToken()
      let request = buildRequest(
        url: url,
        method: method,
        body: body,
        token: token,
        idempotencyKey: idempotencyKey
      )

      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await http.data(for: request)
      } catch {
        if try await shouldRetryAfterFailure(error, attempt: attempt) {
          attempt += 1
          continue
        }
        throw terminalError(from: error)
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        throw ExpysError.network("Non-HTTP response")
      }
      let status = httpResponse.statusCode

      if (200..<300).contains(status) {
        return try decode(data)
      }

      let requestId = httpResponse.value(forHTTPHeaderField: "x-request-id")

      if status == 401, session.canRefresh, !refreshedOn401 {
        refreshedOn401 = true
        try await refreshReactively(data: data, requestId: requestId)
        continue
      }

      if isRetryableStatus(status), attempt < maxRetries {
        try await sleep(retryDelay(attempt: attempt, response: httpResponse))
        attempt += 1
        continue
      }

      throw apiError(status: status, data: data, response: httpResponse, requestId: requestId)
    }
  }

  /// Refresh ahead of expiry. Best effort: a transient failure must not block a
  /// possibly-valid token (the reactive 401 path recovers); cancellation still
  /// propagates and is never swallowed.
  private func refreshProactivelyIfNeeded() async throws {
    guard await session.shouldRefreshProactively() else { return }
    do {
      try await session.refreshToken()
    } catch {
      if isCancellation(error) { throw error }
    }
  }

  /// Decide whether a thrown transport error warrants another attempt. Sleeps the
  /// backoff and returns `true` to retry; rethrows cancellation immediately so
  /// structured-concurrency teardown is honored, never retried.
  private func shouldRetryAfterFailure(_ error: Error, attempt: Int) async throws -> Bool {
    if isCancellation(error) { throw error }
    guard attempt < maxRetries else { return false }
    try await sleep(backoffDelay(attempt: attempt, random: random))
    return true
  }

  /// One reactive refresh on a 401, then retry. A failed refresh propagates the
  /// original 401 as a typed error (cancellation still propagates).
  private func refreshReactively(data: Data, requestId: String?) async throws {
    do {
      try await session.refreshToken()
    } catch {
      if isCancellation(error) { throw error }
      throw mapAPIError(status: 401, data: data, retryAfterMs: nil, requestId: requestId)
    }
  }

  private func decode<T: Decodable>(_ data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw ExpysError.decoding(String(describing: error))
    }
  }

  /// The sleep before a retryable-status (429/5xx) retry: honor `Retry-After`
  /// when present, otherwise full-jitter backoff.
  private func retryDelay(attempt: Int, response: HTTPURLResponse) -> TimeInterval {
    parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: now())
      ?? backoffDelay(attempt: attempt, random: random)
  }

  /// A non-cancellation request failure mapped to a typed terminal error.
  private func terminalError(from error: Error) -> ExpysError {
    isTimeout(error) ? .timeout : .network(String(describing: error))
  }

  /// The typed error for an exhausted/non-retryable non-2xx response. The
  /// `Retry-After` is parsed in seconds for the sleep above but surfaced on the
  /// error in ms for parity with the TS/Kotlin SDKs (429 only).
  private func apiError(
    status: Int,
    data: Data,
    response: HTTPURLResponse,
    requestId: String?
  ) -> ExpysError {
    let retryAfterMs =
      status == 429
      ? parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: now())
        .map { Int(($0 * 1000).rounded()) }
      : nil
    return mapAPIError(status: status, data: data, retryAfterMs: retryAfterMs, requestId: requestId)
  }

  private func buildURL(path: String, query: [String: String?]) throws -> URL {
    guard var components = URLComponents(string: baseURL.absoluteString + path) else {
      throw ExpysError.network("Invalid URL for path \(path)")
    }
    let items =
      query
      .compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
      .sorted { $0.name < $1.name }
    if !items.isEmpty {
      components.queryItems = items
    }
    guard let url = components.url else {
      throw ExpysError.network("Invalid URL for path \(path)")
    }
    return url
  }

  private func buildRequest(
    url: URL,
    method: String,
    body: Data?,
    token: String,
    idempotencyKey: String?
  ) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if let idempotencyKey {
      request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
    }
    if let timeout {
      request.timeoutInterval = timeout
    }
    return request
  }

  private func isTimeout(_ error: Error) -> Bool {
    return (error as? URLError)?.code == .timedOut
  }

  /// Task cancellation, whether surfaced as a `CancellationError` (e.g. a
  /// cancelled `Task.sleep`) or URLSession's `URLError.cancelled`. Such errors
  /// must propagate so structured-concurrency cancellation works, matching the
  /// Kotlin SDK (which rethrows CancellationException).
  private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    return (error as? URLError)?.code == .cancelled
  }
}
