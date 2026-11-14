import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// One offer by id, the org's authored display prices, and the org's display currency.
/// The price and configuration writes are server-only and need the `CONFIG_WRITE` scope.
extension ExpysClient {
  /// Read one offer by its id: the same shape ``listOffers(limit:cursor:available:)``
  /// returns, for a deep link. Works with a member token or a machine credential.
  /// - Parameter id: The offer id.
  /// - Returns: The ``Offer``.
  /// - Throws: ``ExpysError/api(_:)`` with `kind == .notFound` when no offer with that
  ///   id is visible to your org (another tenant's id gets the same 404).
  public func getOffer(id: String) async throws -> Offer {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await transport.request(method: "GET", path: "/v1/offers/\(encoded)")
  }

  /// Set the org's own display price for one experience, in your currency. Your members
  /// see this amount instead of the derived figure; the points debited on redemption are
  /// unchanged. Idempotent by HTTP semantics (PUT), so no idempotency key is sent.
  /// - Parameters:
  ///   - id: The offer id.
  ///   - input: The `amount` to display (0 or more; decimals allowed).
  /// - Returns: The ``Offer`` as your members now see it (`display.source == .authored`).
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token;
  ///   ``ExpysError/api(_:)`` with `kind == .notFound` when the offer is not visible to
  ///   your org, or `kind == .validation` when the amount is negative.
  public func setOfferPrice(id: String, _ input: SetOfferPriceRequest) async throws -> Offer {
    try assertMachineCredential(configuredToken, method: "setOfferPrice")
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let body = try ExpysJSON.encoder().encode(input)
    return try await transport.request(
      method: "PUT", path: "/v1/offers/\(encoded)/price", body: body)
  }

  /// Clear the org's authored display price for one experience, reverting it to the
  /// figure derived from the dollar price and your currency ratio. Idempotent by HTTP
  /// semantics (DELETE), so no idempotency key is sent.
  /// - Parameter id: The offer id.
  /// - Returns: The ``Offer`` as your members now see it (`display.source == .derived`).
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func deleteOfferPrice(id: String) async throws -> Offer {
    try assertMachineCredential(configuredToken, method: "deleteOfferPrice")
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await transport.request(method: "DELETE", path: "/v1/offers/\(encoded)/price")
  }

  /// Name the org's display currency and set how many units of it make a dollar. Send
  /// only the fields you are changing. Idempotent by HTTP semantics (PUT), so no
  /// idempotency key is sent. A ratio change large enough to reprice the catalogue past
  /// the guard factor is refused unless `confirmReprice` is true.
  /// - Parameter input: Any of `currencyName`, `currencySymbol`, `currencyUnitsPerUSD`,
  ///   and `confirmReprice`.
  /// - Returns: The org's currency after the change.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token;
  ///   ``ExpysError/api(_:)`` with status 400 when the input is invalid or the reprice
  ///   needs confirming, or code `FIELD_NOT_WRITABLE` when it names a commercial term.
  public func updateConfiguration(
    _ input: UpdateConfigurationRequest
  ) async throws -> UpdateConfigurationResponse {
    try assertMachineCredential(configuredToken, method: "updateConfiguration")
    let body = try ExpysJSON.encoder().encode(input)
    return try await transport.request(method: "PUT", path: "/v1/configuration", body: body)
  }
}
