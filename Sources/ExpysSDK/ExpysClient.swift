import Foundation

/// The Expys data SDK client. Configure once with a short-lived member token and
/// an optional refresh closure; every call retries 429/5xx with backoff and
/// sends an idempotency key on writes.
public struct ExpysClient: Sendable {
  private let transport: Transport
  private let streamTransport: StreamTransport
  /// The credential the client was configured with. Server-mode methods check it
  /// is a machine (Org-API-Key) credential before issuing any request. Machine
  /// credentials are long-lived and never refreshed, so this is authoritative.
  private let configuredToken: String

  /// Creates a client from a configuration.
  /// - Parameters:
  ///   - configuration: Token, environment, retry/refresh policy. See ``ExpysConfiguration``.
  ///   - httpClient: Injectable HTTP layer; defaults to a `URLSession`-backed one.
  ///     Override it to instrument requests or supply a stub in tests.
  /// ```swift
  /// let client = ExpysClient(configuration: ExpysConfiguration(token: memberToken))
  /// ```
  public init(
    configuration: ExpysConfiguration,
    httpClient: HTTPRequesting? = nil
  ) {
    self.configuredToken = configuration.token
    let http = httpClient ?? URLSessionHTTP()
    let session = ExpysSession(
      token: configuration.token,
      expiresAt: configuration.tokenExpiresAt,
      refresh: configuration.refreshToken,
      skew: configuration.refreshSkew,
      now: { Date() }
    )
    let userAgent = ExpysVersion.buildUserAgent(
      environment: configuration.environment,
      orgID: configuration.orgID,
      suffix: configuration.userAgentSuffix
    )
    let sleep: @Sendable (TimeInterval) async throws -> Void = {
      try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
    }

    self.transport = Transport(
      baseURL: configuration.baseURL,
      session: session,
      http: http,
      maxRetries: configuration.maxRetries,
      userAgent: userAgent,
      timeout: configuration.timeout,
      sleep: sleep,
      now: { Date() },
      random: { Double.random(in: 0..<1) }
    )
    self.streamTransport = StreamTransport(
      baseURL: configuration.baseURL,
      session: session,
      http: URLSessionStreamingHTTP(),
      userAgent: userAgent,
      timeout: configuration.timeout,
      sleep: sleep,
      now: { Date() },
      random: { Double.random(in: 0..<1) }
    )
  }

  /// Internal initializer for tests with injectable transports. `configuredToken`
  /// defaults to a machine credential so server-mode tests pass the guard; the
  /// guard test overrides it with a member token.
  init(
    transport: Transport,
    streamTransport: StreamTransport,
    configuredToken: String = "expys_test_machine"
  ) {
    self.transport = transport
    self.streamTransport = streamTransport
    self.configuredToken = configuredToken
  }

  /// Browse available offers. Cursor-paginate with `cursor` until the response's
  /// `nextCursor` is nil.
  /// - Parameters:
  ///   - limit: Maximum number of offers to return.
  ///   - cursor: Pagination cursor from a previous response's `nextCursor`.
  /// - Returns: An ``OfferList`` of offers plus the next `nextCursor`.
  public func listOffers(limit: Int? = nil, cursor: String? = nil) async throws -> OfferList {
    try await transport.request(
      method: "GET",
      path: "/v1/offers",
      query: ["limit": limit.map(String.init), "cursor": cursor]
    )
  }

  /// Book (request) an offer for the member. Sends an `Idempotency-Key` so a retry
  /// replays rather than double-books.
  /// - Parameters:
  ///   - input: The offer to redeem (and optionally the externalUserID a machine
  ///     token acts for).
  ///   - idempotencyKey: Override the auto-generated key (e.g. to retry across launches).
  /// - Throws: ``ExpysError/api(_:)`` with `kind == .conflict` (code
  ///   `REDEMPTION_ALREADY_EXISTS`) on 409 when the member already booked this
  ///   offer, or `kind == .validation` with `code == "INSUFFICIENT_POINTS"` on 422
  ///   when the wallet balance is too low.
  public func createRedemption(
    _ input: CreateRedemptionRequest,
    idempotencyKey: String? = nil
  ) async throws -> Redemption {
    let body = try JSONEncoder().encode(input)
    return try await transport.request(
      method: "POST",
      path: "/v1/redemptions",
      body: body,
      idempotencyKey: idempotencyKey ?? generateIdempotencyKey()
    )
  }

  /// Read a redemption by its id. Throws ``ExpysError/api(_:)`` (404 if not found).
  public func getRedemption(id: String) async throws -> Redemption {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await transport.request(method: "GET", path: "/v1/redemptions/\(encoded)")
  }

  /// List the member's redemptions. Cursor-paginate with `cursor` until the
  /// response's `nextCursor` is nil; filter by lifecycle `status`.
  /// - Parameters:
  ///   - status: Lifecycle status filter (`SUBMITTED`, `OPEN`, `AWAITING_VENDOR`,
  ///     `AWAITING_CUSTOMER`, `PURCHASED`, `CANCELED`, `COMPLETED`).
  ///   - limit: Maximum number of redemptions to return (1-100).
  ///   - cursor: Pagination cursor from a previous response's `nextCursor`.
  ///   - externalUserID: Names the member when a machine token calls on their behalf.
  /// - Returns: A ``ListRedemptionsResponse`` plus the next `nextCursor`.
  public func listRedemptions(
    status: String? = nil,
    limit: Int? = nil,
    cursor: String? = nil,
    externalUserID: String? = nil
  ) async throws -> ListRedemptionsResponse {
    try await transport.request(
      method: "GET",
      path: "/v1/redemptions",
      query: [
        "status": status,
        "limit": limit.map(String.init),
        "cursor": cursor,
        "externalUserID": externalUserID,
      ]
    )
  }

  /// List the member's wallet transactions (the points ledger). Cursor-paginate
  /// with `cursor` until the response's `nextCursor` is nil.
  /// - Parameters:
  ///   - limit: Maximum number of transactions to return.
  ///   - cursor: Pagination cursor from a previous response's `nextCursor`.
  ///   - externalUserID: Names the member when a machine token calls on their behalf.
  /// - Returns: A ``ListTransactionsResponse`` plus the next `nextCursor`.
  public func walletTransactions(
    limit: Int? = nil,
    cursor: String? = nil,
    externalUserID: String? = nil
  ) async throws -> ListTransactionsResponse {
    try await transport.request(
      method: "GET",
      path: "/v1/wallet/transactions",
      query: [
        "limit": limit.map(String.init),
        "cursor": cursor,
        "externalUserID": externalUserID,
      ]
    )
  }

  /// List the member's conversations.
  /// - Parameter externalUserID: Names the member when a machine token calls on their behalf.
  /// - Returns: A ``ListConversationsResponse`` of conversations.
  public func listConversations(
    externalUserID: String? = nil
  ) async throws -> ListConversationsResponse {
    try await transport.request(
      method: "GET",
      path: "/v1/conversations",
      query: ["externalUserID": externalUserID]
    )
  }

  /// List the messages in a conversation. Cursor-paginate with `cursor` until the
  /// response's `nextCursor` is nil.
  /// - Parameters:
  ///   - id: The conversation id.
  ///   - limit: Maximum number of messages to return.
  ///   - cursor: Pagination cursor from a previous response's `nextCursor`.
  ///   - externalUserID: Names the member when a machine token calls on their behalf.
  /// - Returns: A ``ListMessagesResponse`` of messages plus the next `nextCursor`.
  public func listMessages(
    id: String,
    limit: Int? = nil,
    cursor: String? = nil,
    externalUserID: String? = nil
  ) async throws -> ListMessagesResponse {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await transport.request(
      method: "GET",
      path: "/v1/conversations/\(encoded)/messages",
      query: [
        "limit": limit.map(String.init),
        "cursor": cursor,
        "externalUserID": externalUserID,
      ]
    )
  }

  /// Send a message into a conversation. Sends an `Idempotency-Key` so a retry
  /// replays rather than double-posts.
  /// - Parameters:
  ///   - id: The conversation id.
  ///   - message: The message body to send.
  ///   - idempotencyKey: Override the auto-generated key (e.g. to retry across launches).
  /// - Returns: A ``SendMessageResponse`` (`ok == true` when accepted).
  public func sendMessage(
    id: String,
    message: String,
    idempotencyKey: String? = nil
  ) async throws -> SendMessageResponse {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    let body = try JSONEncoder().encode(SendMessageRequest(message: message))
    return try await transport.request(
      method: "POST",
      path: "/v1/conversations/\(encoded)/messages",
      body: body,
      idempotencyKey: idempotencyKey ?? generateIdempotencyKey()
    )
  }

  /// Stream new, member-visible messages in a conversation over Server-Sent
  /// Events as they arrive. Returns a lazy `AsyncThrowingStream<Message, Error>`;
  /// consume it with `for try await`. History is not replayed - pair this with
  /// ``listMessages(id:limit:cursor:externalUserID:)`` for the backlog. The stream
  /// reconnects with backoff on transient failures and finishes by throwing an
  /// ``ExpysError/api(_:)`` on a permanent error (`kind == .forbidden` /
  /// `.notFound`, or `.unauthorized` after a failed refresh). Cancelling the
  /// consuming `Task` tears down the connection. Member-only; no `externalUserID`.
  /// - Parameter id: The conversation id.
  /// - Returns: An `AsyncThrowingStream<Message, Error>` of new messages.
  /// ```swift
  /// for try await message in client.streamMessages(id: "cnv_123") {
  ///   print(message.body ?? "")
  /// }
  /// ```
  public func streamMessages(id: String) -> AsyncThrowingStream<Message, Error> {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return streamTransport.stream(path: "/v1/conversations/\(encoded)/stream")
  }

  /// The member's eligibility (tier + wallet).
  /// - Parameter externalUserID: Names the member when a machine token calls on their behalf.
  public func eligibility(externalUserID: String? = nil) async throws -> MemberEligibility {
    try await transport.request(
      method: "GET",
      path: "/v1/eligibility",
      query: ["externalUserID": externalUserID]
    )
  }

  /// The member's wallet (balances).
  public func wallet() async throws -> Wallet {
    try await transport.request(method: "GET", path: "/v1/wallet")
  }

  // MARK: - Server-mode methods
  //
  // Server-mode methods require an Org-API-Key machine credential. Each guards the
  // configured token BEFORE any request and throws ``ExpysError/notConfigured(_:)``
  // when a member token was supplied. The server also 403s a member token, but the
  // SDK fails fast.

  /// Exchange this org's credential for a short-lived member token. Sends an
  /// `Idempotency-Key` so a retry replays rather than re-mints. Server-only.
  /// - Parameters:
  ///   - input: The member to mint a token for (`externalUserID`) plus optional profile fields.
  ///   - idempotencyKey: Override the auto-generated key.
  /// - Returns: A ``TokenGrant`` (`accessToken` + `expiresAt`).
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func exchangeToken(
    _ input: TokenExchangeRequest,
    idempotencyKey: String? = nil
  ) async throws -> TokenGrant {
    try assertMachineCredential(configuredToken, method: "exchangeToken")
    let body = try JSONEncoder().encode(input)
    return try await transport.request(
      method: "POST",
      path: "/v1/auth/exchange",
      body: body,
      idempotencyKey: idempotencyKey ?? generateIdempotencyKey()
    )
  }

  /// Credit points to a member's wallet. Sends an `Idempotency-Key` so a retry
  /// replays rather than double-credits. Server-only.
  /// - Parameters:
  ///   - input: The ``CreditWalletRequest`` (`amount`, `externalUserID`, optional `reason`).
  ///   - idempotencyKey: Override the auto-generated key.
  /// - Returns: A ``CreditWalletResponse`` with the member's new balance.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func creditPoints(
    _ input: CreditWalletRequest,
    idempotencyKey: String? = nil
  ) async throws -> CreditWalletResponse {
    try assertMachineCredential(configuredToken, method: "creditPoints")
    let body = try JSONEncoder().encode(input)
    return try await transport.request(
      method: "POST",
      path: "/v1/wallet/credit",
      body: body,
      idempotencyKey: idempotencyKey ?? generateIdempotencyKey()
    )
  }

  /// Upsert a member's profile (tier, display name, attributes) by their external
  /// id. Idempotent by HTTP semantics (PUT), so no idempotency key is sent. Server-only.
  /// - Parameters:
  ///   - externalUserID: The member's external user id.
  ///   - input: The fields to upsert.
  /// - Returns: A ``SetMemberResponse``.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func setMember(
    externalUserID: String,
    _ input: SetMemberRequest
  ) async throws -> SetMemberResponse {
    try assertMachineCredential(configuredToken, method: "setMember")
    let encoded =
      externalUserID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      ?? externalUserID
    let body = try JSONEncoder().encode(input)
    return try await transport.request(method: "PUT", path: "/v1/members/\(encoded)", body: body)
  }

  /// Read a member's profile by their external id. Server-only.
  /// - Parameter externalUserID: The member's external user id.
  /// - Returns: A ``MemberSummary``.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func getMember(externalUserID: String) async throws -> MemberSummary {
    try assertMachineCredential(configuredToken, method: "getMember")
    let encoded =
      externalUserID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      ?? externalUserID
    return try await transport.request(method: "GET", path: "/v1/members/\(encoded)")
  }

  /// Remove (archive) a member by their external id. Idempotent by HTTP semantics
  /// (DELETE), so no idempotency key is sent. Server-only.
  /// - Parameters:
  ///   - externalUserID: The member's external user id.
  ///   - retainBalance: Keep the member's points balance instead of clearing it.
  /// - Returns: A ``RemoveMemberResponse``.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func removeMember(
    externalUserID: String,
    retainBalance: Bool? = nil
  ) async throws -> RemoveMemberResponse {
    try assertMachineCredential(configuredToken, method: "removeMember")
    let encoded =
      externalUserID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      ?? externalUserID
    return try await transport.request(
      method: "DELETE",
      path: "/v1/members/\(encoded)",
      query: ["retainBalance": retainBalance.map { $0 ? "true" : "false" }]
    )
  }

  /// Org-wide analytics rollups (members, points minted/spent, completion rate).
  /// Server-only.
  /// - Returns: A ``GetAnalyticsSummaryResponse``.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func analyticsSummary() async throws -> GetAnalyticsSummaryResponse {
    try assertMachineCredential(configuredToken, method: "analyticsSummary")
    return try await transport.request(method: "GET", path: "/v1/analytics/summary")
  }

  /// Per-offer analytics rollups for the org. Server-only.
  /// - Returns: A ``GetAnalyticsOffersResponse``.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func analyticsOffers() async throws -> GetAnalyticsOffersResponse {
    try assertMachineCredential(configuredToken, method: "analyticsOffers")
    return try await transport.request(method: "GET", path: "/v1/analytics/offers")
  }

  /// Time-bucketed analytics over a window. Server-only.
  /// - Parameters:
  ///   - from: Start of the window, an ISO-8601 date-time string. Required.
  ///   - to: End of the window, an ISO-8601 date-time string. Required.
  ///   - interval: Bucket interval: `day`, `week`, or `month`. Required.
  /// - Returns: A ``GetAnalyticsTimeseriesResponse`` of buckets.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func analyticsTimeseries(
    from: String,
    to: String,
    interval: String
  ) async throws -> GetAnalyticsTimeseriesResponse {
    try assertMachineCredential(configuredToken, method: "analyticsTimeseries")
    return try await transport.request(
      method: "GET",
      path: "/v1/analytics/timeseries",
      query: ["from": from, "to": to, "interval": interval]
    )
  }

  /// Register a webhook endpoint. Sends an `Idempotency-Key` so a retry replays
  /// rather than double-registers. Server-only.
  /// - Parameters:
  ///   - input: The webhook `events` and delivery `url`.
  ///   - idempotencyKey: Override the auto-generated key.
  /// - Returns: A ``WebhookEndpointWithSecret`` (the `signingSecret` is shown only on creation).
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func createWebhook(
    _ input: CreateWebhookRequest,
    idempotencyKey: String? = nil
  ) async throws -> WebhookEndpointWithSecret {
    try assertMachineCredential(configuredToken, method: "createWebhook")
    let body = try JSONEncoder().encode(input)
    return try await transport.request(
      method: "POST",
      path: "/v1/webhooks",
      body: body,
      idempotencyKey: idempotencyKey ?? generateIdempotencyKey()
    )
  }

  /// List the org's webhook endpoints. Server-only.
  /// - Returns: A ``WebhookEndpointList``.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func listWebhooks() async throws -> WebhookEndpointList {
    try assertMachineCredential(configuredToken, method: "listWebhooks")
    return try await transport.request(method: "GET", path: "/v1/webhooks")
  }

  /// Delete a webhook endpoint by its id. Server-only.
  /// - Parameter id: The webhook id.
  /// - Returns: A ``DeleteWebhookResponse``.
  /// - Throws: ``ExpysError/notConfigured(_:)`` when configured with a member token.
  public func deleteWebhook(id: String) async throws -> DeleteWebhookResponse {
    try assertMachineCredential(configuredToken, method: "deleteWebhook")
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return try await transport.request(method: "DELETE", path: "/v1/webhooks/\(encoded)")
  }
}
