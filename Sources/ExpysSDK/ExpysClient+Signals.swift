import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The VIP signals surface: bulk upserts, a member's signal history, and the
/// segments and lift analytics built from signals. Server-only, like the rest of the
/// members and analytics surface.
extension ExpysClient {
  /// Upsert up to 1,000 members in one call; each row takes the fields of
  /// ``setMember(externalUserID:_:)`` (`tier`, `signals`, `attributes`, `asOf`). A bad
  /// row is skipped and listed in the report with its 1-based row number, field and
  /// code; every other row is written. Sends an `Idempotency-Key` (the route requires
  /// one) so a retry replays the original report. Requires the `MEMBERS_WRITE` scope.
  /// - Parameters:
  ///   - input: The rows to import.
  ///   - dryRun: Check every row and return the report without writing anything.
  ///   - idempotencyKey: Override the auto-generated key.
  /// - Returns: A ``MemberImportReport``: `accepted` and the `rejected` rows.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func importMembers(
    _ input: ImportMembersRequest,
    dryRun: Bool = false,
    idempotencyKey: String? = nil
  ) async throws -> MemberImportReport {
    try assertMachineCredential(configuredToken, method: "importMembers")
    let body = try ExpysJSON.encoder().encode(input)
    return try await transport.request(
      method: "POST",
      path: "/v1/members/batch",
      query: ["dryRun": dryRun ? "true" : nil],
      body: body,
      idempotencyKey: idempotencyKey ?? generateIdempotencyKey()
    )
  }

  /// Read a member's VIP signal history: one snapshot of their full signal set per
  /// change, newest first by `observedAt`. Cursor-paginate with `cursor` until the
  /// response's `nextCursor` is nil. Requires the `MEMBERS_READ` scope.
  /// - Parameters:
  ///   - externalUserID: The member's external user id.
  ///   - from: Only snapshots observed at or after this time (ISO 8601, inclusive).
  ///   - to: Only snapshots observed at or before this time (ISO 8601, inclusive).
  ///   - limit: Maximum number of snapshots to return (1-100).
  ///   - cursor: Pagination cursor from a previous response's `nextCursor`.
  /// - Returns: A ``ListMemberSignalHistoryResponse`` plus the next `nextCursor`.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func getSignalHistory(
    externalUserID: String,
    from: String? = nil,
    to: String? = nil,
    limit: Int? = nil,
    cursor: String? = nil
  ) async throws -> ListMemberSignalHistoryResponse {
    try assertMachineCredential(configuredToken, method: "getSignalHistory")
    let encoded =
      externalUserID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      ?? externalUserID
    return try await transport.request(
      method: "GET",
      path: "/v1/members/\(encoded)/signals/history",
      query: [
        "from": from,
        "to": to,
        "limit": limit.map(String.init),
        "cursor": cursor,
      ]
    )
  }

  /// VIP counts, bookings and top categories per segment, grouping VIPs by one or two
  /// signal fields (`vipStatus` counts as a field). Reads live data only, so a sandbox
  /// key gets no segments. A segment with fewer than 5 VIPs comes back with
  /// `suppressed == true` and its counts nil. Requires the `ANALYTICS_READ` scope.
  /// - Parameters:
  ///   - from: Start of the period (inclusive), an ISO-8601 date-time string.
  ///   - to: End of the period (exclusive), an ISO-8601 date-time string.
  ///   - groupBy: One or two fields, each switched on for your org (`vipStatus`
  ///     needs `activityBand`).
  /// - Returns: A ``GetAnalyticsSegmentsResponse`` of segments.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func getAnalyticsSegments(
    from: String,
    to: String,
    groupBy: [GetAnalyticsSegmentsResponse.GroupBy]
  ) async throws -> GetAnalyticsSegmentsResponse {
    try assertMachineCredential(configuredToken, method: "getAnalyticsSegments")
    return try await transport.request(
      method: "GET",
      path: "/v1/analytics/segments",
      query: [
        "from": from,
        "to": to,
        "groupBy": groupBy.map(\.rawValue).joined(separator: ","),
      ]
    )
  }

  /// How the activity of VIPs who booked an experience in the period moved, against
  /// similar VIPs (same `valueBand` + `vipStatus` at the period start) who did not.
  /// Association, not cause. Reads live data only, so a sandbox key gets no groups. A
  /// cohort with fewer than 5 VIPs comes back with `suppressed == true` and every
  /// number nil. Requires the `ANALYTICS_READ` scope.
  /// - Parameters:
  ///   - from: Start of the period (inclusive), an ISO-8601 date-time string.
  ///   - to: End of the period (exclusive), an ISO-8601 date-time string.
  /// - Returns: A ``GetAnalyticsLiftResponse`` of groups.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func getAnalyticsLift(from: String, to: String) async throws -> GetAnalyticsLiftResponse {
    try assertMachineCredential(configuredToken, method: "getAnalyticsLift")
    return try await transport.request(
      method: "GET",
      path: "/v1/analytics/lift",
      query: ["from": from, "to": to]
    )
  }
}
