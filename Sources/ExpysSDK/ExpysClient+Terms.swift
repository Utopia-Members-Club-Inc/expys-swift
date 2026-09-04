import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Legal documents and post-experience feedback.
///
/// See ``ExpysClient/createInterest(_:idempotencyKey:)`` for why these live in an
/// extension rather than in the main client file.
extension ExpysClient {
  /// List the legal documents this member has and has not accepted.
  ///
  /// Metadata only — safe to call on every launch. The document text is a separate,
  /// cacheable call: see ``getTermsContent(version:)``.
  ///
  /// `acceptedAt` is nil while a document is outstanding, including when the member
  /// accepted an earlier version of it.
  public func getTerms(externalUserID: String? = nil) async throws -> GetTermsResponse {
    try await transport.request(
      method: "GET",
      path: "/v1/terms",
      query: ["externalUserID": externalUserID]
    )
  }

  /// Read one version's text, rendered for your organisation.
  ///
  /// A published version never changes, so this response is stable forever and is served
  /// `Cache-Control: immutable`. Fetch it when the consent sheet opens, not on launch —
  /// the terms of service are around 28kB.
  public func getTermsContent(
    version: String
  ) async throws -> GetTermsContentResponse {
    let encoded =
      version.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? version
    return try await transport.request(method: "GET", path: "/v1/terms/\(encoded)/content")
  }

  /// Record that the member accepted one or more document versions. Sends an
  /// `Idempotency-Key` so a retry replays rather than double-records.
  ///
  /// Re-accepting a version already on file is a no-op, not an error. The response is
  /// the same shape as ``getTerms(externalUserID:)``, so a consent sheet can dismiss
  /// without a second call.
  public func acceptTerms(
    _ input: AcceptTermsRequest,
    idempotencyKey: String? = nil
  ) async throws -> GetTermsResponse {
    let body = try JSONEncoder().encode(input)
    return try await transport.request(
      method: "POST",
      path: "/v1/terms/acceptance",
      body: body,
      idempotencyKey: idempotencyKey ?? generateIdempotencyKey()
    )
  }

  /// Record a member's score for a completed experience. 0–10, the NPS scale.
  ///
  /// Throws ``ExpysError/api(_:)`` with code `REDEMPTION_NOT_COMPLETED` when the
  /// experience has not happened yet; its `details.status` names the current one.
  public func setRedemptionFeedback(
    id: String,
    _ input: SetRedemptionFeedbackRequest
  ) async throws -> Redemption {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let body = try JSONEncoder().encode(input)
    return try await transport.request(
      method: "PUT",
      path: "/v1/redemptions/\(encoded)/feedback",
      body: body
    )
  }
}
