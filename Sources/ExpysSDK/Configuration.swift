// `@preconcurrency` silences cross-module Sendable warnings for Foundation types
// (e.g. `URL`) that are not yet `Sendable` on the Swift 6.0/6.1 toolchains CI uses;
// newer toolchains already mark them `Sendable`, where the attribute is a harmless
// no-op. `ExpysConfiguration` stores a `URL` and conforms to `Sendable`.
@preconcurrency import Foundation

/// The credential's environment. Sandbox and live share one host; the
/// environment is enforced server-side as a token claim.
public enum ExpysEnvironment: String, Sendable {
  case sandbox
  case live
}

/// Result of a token refresh: a fresh short-lived member token and its expiry.
///
/// Return one from your ``ExpysConfiguration/refreshToken`` hook:
/// ```swift
/// refreshToken: {
///   let (data, _) = try await URLSession.shared.data(from: refreshURL)
///   return try JSONDecoder().decode(TokenRefresh.self, from: data)
/// }
/// ```
public struct TokenRefresh: Sendable {
  /// The fresh short-lived member token to use for subsequent requests.
  public let accessToken: String
  /// When the new token expires. Provide it to re-arm proactive refresh; omit it
  /// to rely solely on reactive (401) refresh.
  public let expiresAt: Date?

  /// Creates a refresh result from a new token and its optional expiry.
  public init(accessToken: String, expiresAt: Date? = nil) {
    self.accessToken = accessToken
    self.expiresAt = expiresAt
  }
}

/// Configures an `ExpysClient`. Holds a short-lived member token obtained by your
/// backend via `POST /v1/auth/exchange`; the Org-API-Key never ships in the app.
public struct ExpysConfiguration: Sendable {
  /// Default API host (the canonical public domain). Sandbox and live share one
  /// host (environment is a token claim, not a host switch).
  public static let defaultBaseURL = URL(string: "https://api.expys.com")!

  /// Short-lived member token your backend obtained from `POST /v1/auth/exchange`.
  /// Sent as a bearer token; the Org-API-Key must never ship in the app.
  public var token: String
  /// Informational environment (`.live` default / `.sandbox`). Enforced
  /// server-side by the token claim; the SDK only surfaces it in the `User-Agent`.
  public var environment: ExpysEnvironment
  /// API host. Sandbox and live share one host, so this rarely changes.
  public var baseURL: URL
  /// Optional organization id, folded into the `User-Agent` for attribution.
  public var orgID: String?
  /// When `token` expires. Enables proactive refresh within `refreshSkew`; omit
  /// it to rely solely on reactive (401) refresh.
  public var tokenExpiresAt: Date?
  /// Called to obtain a fresh token; should hit your backend, which re-exchanges
  /// the Org-API-Key. Without it, an expired token simply 401s.
  public var refreshToken: (@Sendable () async throws -> TokenRefresh)?
  /// Additional attempts after the first on retryable (429/5xx) failures.
  public var maxRetries: Int
  /// Per-request timeout in seconds. Defaults to URLSession's default.
  public var timeout: TimeInterval?
  /// Refresh this long before expiry.
  public var refreshSkew: TimeInterval
  /// Appended to the SDK User-Agent (e.g. your app name/version).
  public var userAgentSuffix: String?

  /// Creates a configuration. Only `token` is required; every other option has a
  /// cross-SDK default (`environment: .live`, `maxRetries: 2`, `refreshSkew: 30`).
  /// ```swift
  /// let config = ExpysConfiguration(token: memberToken, environment: .sandbox)
  /// ```
  public init(
    token: String,
    environment: ExpysEnvironment = .live,
    baseURL: URL = ExpysConfiguration.defaultBaseURL,
    orgID: String? = nil,
    tokenExpiresAt: Date? = nil,
    refreshToken: (@Sendable () async throws -> TokenRefresh)? = nil,
    maxRetries: Int = 2,
    timeout: TimeInterval? = nil,
    refreshSkew: TimeInterval = 30,
    userAgentSuffix: String? = nil
  ) {
    self.token = token
    self.environment = environment
    self.baseURL = baseURL
    self.orgID = orgID
    self.tokenExpiresAt = tokenExpiresAt
    self.refreshToken = refreshToken
    self.maxRetries = maxRetries
    self.timeout = timeout
    self.refreshSkew = refreshSkew
    self.userAgentSuffix = userAgentSuffix
  }
}
