import Foundation

/// Holds the member token and refreshes it via the configured closure. An actor
/// so the mutable token state is safe under concurrent requests.
actor ExpysSession {
  private var token: String
  private var expiresAt: Date?
  private let refresh: (@Sendable () async throws -> TokenRefresh)?
  private let skew: TimeInterval
  private let nowProvider: @Sendable () -> Date

  /// Whether a refresh closure was configured (immutable, sync-accessible).
  nonisolated let canRefresh: Bool

  init(
    token: String,
    expiresAt: Date?,
    refresh: (@Sendable () async throws -> TokenRefresh)?,
    skew: TimeInterval,
    now: @escaping @Sendable () -> Date
  ) {
    self.token = token
    self.expiresAt = expiresAt
    self.refresh = refresh
    self.skew = skew
    self.nowProvider = now
    self.canRefresh = refresh != nil
  }

  func currentToken() -> String { token }

  func shouldRefreshProactively() -> Bool {
    guard canRefresh, let expiresAt else { return false }
    return nowProvider().addingTimeInterval(skew) >= expiresAt
  }

  func refreshToken() async throws {
    guard let refresh else {
      throw ExpysError.notConfigured("No refreshToken closure was configured")
    }
    let result = try await refresh()
    token = result.accessToken
    expiresAt = result.expiresAt
  }
}
