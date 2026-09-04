import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The interest surface: a member says they want an experience, gets a concierge
/// conversation and somewhere to put their dates, and spends nothing.
///
/// Split into its own file rather than growing ``ExpysClient`` further — SwiftLint caps a
/// type body at 300 lines, and a flat facade over a growing API will keep meeting that
/// cap. Extensions are the idiomatic answer and they group the surface by subject.
extension ExpysClient {
  /// Register interest in an experience: opens a concierge conversation and carries the
  /// member's dates, with **no points debited and no inventory held**. Sends an
  /// `Idempotency-Key` so a retry replays rather than double-registers.
  ///
  /// Dietary, allergy and accessibility answers are not accepted here — send them to
  /// ``setInterestIntake(id:_:)``, which does not store them.
  public func createInterest(
    _ input: CreateInterestRequest,
    idempotencyKey: String? = nil
  ) async throws -> CreateInterestResponse {
    let body = try JSONEncoder().encode(input)
    return try await transport.request(
      method: "POST",
      path: "/v1/interests",
      body: body,
      idempotencyKey: idempotencyKey ?? generateIdempotencyKey()
    )
  }

  /// Read an interest and its intake.
  public func getInterest(id: String) async throws -> CreateInterestResponse {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await transport.request(method: "GET", path: "/v1/interests/\(encoded)")
  }

  /// Replace an interest's intake. Send the complete answer each time — a partial merge
  /// over a set of dates has no sane meaning.
  ///
  /// The dietary, allergy and accessibility fields are forwarded to the concierge team
  /// and **never stored**: you can send them, you cannot read them back, and the response
  /// records only when they were sent.
  public func setInterestIntake(
    id: String,
    _ input: SetInterestIntakeRequest
  ) async throws -> CreateInterestResponse {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let body = try JSONEncoder().encode(input)
    return try await transport.request(
      method: "PUT",
      path: "/v1/interests/\(encoded)/intake",
      body: body
    )
  }

  /// Send a verification code to the number on an interest's intake.
  ///
  /// Until a number is verified it is display-only and the concierge team will not text
  /// it: an unverified number is one typo away from sending a stranger somebody else's
  /// itinerary.
  public func startPhoneVerification(
    id: String
  ) async throws -> StartPhoneVerificationResponse {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await transport.request(
      method: "POST",
      path: "/v1/interests/\(encoded)/phone/verification"
    )
  }

  /// Confirm a phone verification code.
  ///
  /// `verified == false` is **not** an error: the code was wrong or expired, which is an
  /// ordinary thing for somebody to do. Ask again.
  public func confirmPhoneVerification(
    id: String,
    _ input: ConfirmPhoneVerificationRequest
  ) async throws -> ConfirmPhoneVerificationResponse {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let body = try JSONEncoder().encode(input)
    return try await transport.request(
      method: "PUT",
      path: "/v1/interests/\(encoded)/phone/verification",
      body: body
    )
  }
}
