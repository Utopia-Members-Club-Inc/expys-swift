import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The VIP activity surface: a member's monthly deposits, spend and active days, and
/// the experience impact analytics built from them. Server-only, like the rest of the
/// members and analytics surface.
extension ExpysClient {
  /// Write a member's monthly activity: 1-24 calendar months, each with `deposits` and
  /// `spend` as an index of the VIP's usual month (`index`, 100 = usual) or, for an org
  /// allowed amounts, as totals in minor units (`amount` + `currency`), and
  /// `activeDays`. A month sent again replaces the stored one; an identical resend
  /// writes nothing. The member must exist. Sends no idempotency key unless one is
  /// given. Requires the `MEMBERS_WRITE` scope.
  /// - Parameters:
  ///   - externalUserID: The member's external user id.
  ///   - input: The months to write, all in one form.
  ///   - idempotencyKey: An optional key; a retry with the same key replays the
  ///     response.
  /// - Returns: A ``MemberActivityWriteResult``: months created, updated and unchanged.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func setMemberActivity(
    externalUserID: String,
    _ input: SetMemberActivityRequest,
    idempotencyKey: String? = nil
  ) async throws -> MemberActivityWriteResult {
    try assertMachineCredential(configuredToken, method: "setMemberActivity")
    let body = try ExpysJSON.encoder().encode(input)
    return try await transport.request(
      method: "PUT",
      path: "/v1/members/\(Self.encodePath(externalUserID))/activity",
      body: body,
      idempotencyKey: idempotencyKey
    )
  }

  /// Read a member's monthly activity: the stored months, newest first, in the form
  /// they were sent (`form` is nil when there are none). Requires the `MEMBERS_READ`
  /// scope.
  /// - Parameter externalUserID: The member's external user id.
  /// - Returns: The member's ``MemberActivity``.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func getMemberActivity(externalUserID: String) async throws -> MemberActivity {
    try assertMachineCredential(configuredToken, method: "getMemberActivity")
    return try await transport.request(
      method: "GET",
      path: "/v1/members/\(Self.encodePath(externalUserID))/activity"
    )
  }

  /// Write monthly activity for up to 1,000 VIPs and 24,000 months in one call; each
  /// row is an external user id and that VIP's months, each the shape of one month of
  /// ``setMemberActivity(externalUserID:_:idempotencyKey:)``. A bad month is listed in
  /// the report with its 1-based row, field and code; every other month is written.
  /// Counts are months. Sends an `Idempotency-Key` (the route requires one) so a retry
  /// replays the original report. Requires the `MEMBERS_WRITE` scope.
  /// - Parameters:
  ///   - input: The rows to import.
  ///   - dryRun: Check and diff every month and return the report without writing.
  ///   - idempotencyKey: Override the auto-generated key.
  /// - Returns: A ``MemberActivityImportReport``, counted in months.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func importMemberActivity(
    _ input: ImportMemberActivityRequest,
    dryRun: Bool = false,
    idempotencyKey: String? = nil
  ) async throws -> MemberActivityImportReport {
    try assertMachineCredential(configuredToken, method: "importMemberActivity")
    let body = try ExpysJSON.encoder().encode(input)
    return try await transport.request(
      method: "POST",
      path: "/v1/members/activity/batch",
      query: ["dryRun": dryRun ? "true" : nil],
      body: body,
      idempotencyKey: idempotencyKey ?? generateIdempotencyKey()
    )
  }

  /// Experience impact per redemption: for each confirmed redemption in the period (on
  /// the redemption date), newest first, how the VIP's monthly deposits and spend moved
  /// in the months after against the months before, next to the median change of
  /// similar VIPs who redeemed nothing over the same months, and the net. Reads live
  /// data only, so a sandbox key gets no rows. Cursor-paginate with `cursor` until the
  /// response's `nextCursor` is nil. Requires the `ANALYTICS_READ` scope.
  /// - Parameters:
  ///   - from: Start of the period (inclusive), an ISO-8601 date-time string.
  ///   - to: End of the period (exclusive), an ISO-8601 date-time string.
  ///   - window: Months each side of the redemption month: 3 (the default) or 6.
  ///   - offer: Only this experience's redemptions (an offer id as in `listOffers`).
  ///   - status: Only rows in this state.
  ///   - limit: Maximum number of rows to return (1-200, default 50).
  ///   - cursor: Pagination cursor from a previous response's `nextCursor`.
  /// - Returns: An ``ExperienceImpactPage`` of rows plus the next `nextCursor`.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func getExperienceImpact(
    from: String,
    to: String,
    window: Int? = nil,
    offer: String? = nil,
    status: ExperienceImpactRow.State? = nil,
    limit: Int? = nil,
    cursor: String? = nil
  ) async throws -> ExperienceImpactPage {
    try assertMachineCredential(configuredToken, method: "getExperienceImpact")
    return try await transport.request(
      method: "GET",
      path: "/v1/analytics/impact",
      query: [
        "from": from,
        "to": to,
        "window": window.map(String.init),
        "offer": offer,
        "status": status?.rawValue,
        "limit": limit.map(String.init),
        "cursor": cursor,
      ]
    )
  }

  /// Experience impact by experience and for all experiences, for one metric:
  /// redeemers, their median change, similar VIPs' median change and the net lift,
  /// plus the win-back line (cooling VIPs a host sent an experience to against those
  /// sent nothing, on deposits). A cell under 5 redeemers comes back with
  /// `suppressed == true` and every figure nil. Reads live data only. Requires the
  /// `ANALYTICS_READ` scope.
  /// - Parameters:
  ///   - from: Start of the period (inclusive), an ISO-8601 date-time string.
  ///   - to: End of the period (exclusive), an ISO-8601 date-time string.
  ///   - window: Months each side of the redemption month: 3 (the default) or 6.
  ///   - metric: The metric to summarise: deposits (the default) or spend.
  /// - Returns: An ``ExperienceImpactSummary``.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func getExperienceImpactSummary(
    from: String,
    to: String,
    window: Int? = nil,
    metric: ExperienceImpactSummary.Metric? = nil
  ) async throws -> ExperienceImpactSummary {
    try assertMachineCredential(configuredToken, method: "getExperienceImpactSummary")
    return try await transport.request(
      method: "GET",
      path: "/v1/analytics/impact/summary",
      query: [
        "from": from,
        "to": to,
        "window": window.map(String.init),
        "metric": metric?.rawValue,
      ]
    )
  }

  /// A path segment percent-encoded as the other member routes encode it.
  private static func encodePath(_ segment: String) -> String {
    segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? segment
  }
}
