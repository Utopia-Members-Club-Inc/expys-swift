import Foundation

/// A non-2xx API response, carrying the stable envelope `code`.
public struct APIError: Error, Sendable, Equatable {
  /// Coarse category derived from the HTTP status, for ergonomic switching.
  public enum Kind: Sendable, Equatable {
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case validation
    case rateLimited
    case server
    case other
  }

  /// HTTP status code of the failing response.
  public let status: Int
  /// Stable machine-readable code, e.g. "REDEMPTION_ALREADY_EXISTS".
  public let code: String
  /// Human-readable message from the server envelope (not for branching on).
  public let message: String
  /// Milliseconds to wait before retrying, parsed from Retry-After (429 only).
  /// Milliseconds (not seconds) for parity with the TypeScript and Kotlin SDKs.
  public let retryAfterMs: Int?
  /// Server-assigned correlation id from the `x-request-id` response header, when
  /// present. Quote it to support to trace the failure in the server logs.
  public let requestId: String?

  /// Creates an API error. Normally constructed by the SDK from a non-2xx
  /// response; exposed for tests and for re-throwing.
  public init(
    status: Int,
    code: String,
    message: String,
    retryAfterMs: Int? = nil,
    requestId: String? = nil
  ) {
    self.status = status
    self.code = code
    self.message = message
    self.retryAfterMs = retryAfterMs
    self.requestId = requestId
  }

  /// Coarse category derived from ``status``. Switch on this for ergonomic
  /// handling, then refine with ``code`` for the specific case.
  public var kind: Kind {
    switch status {
    case 401: return .unauthorized
    case 403: return .forbidden
    case 404: return .notFound
    case 409: return .conflict
    case 422: return .validation
    case 429: return .rateLimited
    default: return status >= 500 ? .server : .other
    }
  }
}

/// Every error thrown by the SDK.
public enum ExpysError: Error, Sendable {
  case api(APIError)
  case network(String)
  case timeout
  case decoding(String)
  case notConfigured(String)
}

private struct ErrorEnvelope: Decodable {
  struct Body: Decodable {
    let code: String
    let message: String
  }
  let error: Body
}

private let statusCodeDefaults: [Int: String] = [
  400: "BAD_REQUEST",
  401: "UNAUTHORIZED",
  403: "FORBIDDEN",
  404: "NOT_FOUND",
  409: "CONFLICT",
  413: "PAYLOAD_TOO_LARGE",
  422: "UNPROCESSABLE_ENTITY",
  429: "RATE_LIMITED",
  500: "INTERNAL",
]

/// Maps an HTTP status + response body to a typed `.api` error, preserving the
/// envelope code when present and falling back to status defaults otherwise.
/// `requestId` is the `x-request-id` response header when present.
func mapAPIError(
  status: Int,
  data: Data,
  retryAfterMs: Int?,
  requestId: String? = nil
) -> ExpysError {
  let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
  let code = envelope?.error.code ?? statusCodeDefaults[status] ?? "ERROR"
  let message = envelope?.error.message ?? "Request failed with status \(status)"
  return .api(
    APIError(
      status: status,
      code: code,
      message: message,
      retryAfterMs: retryAfterMs,
      requestId: requestId
    )
  )
}
