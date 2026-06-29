import Foundation

/// Generates an idempotency key (a lowercased UUIDv4) for a write. The SDK calls
/// this automatically per `createRedemption`; call it yourself to pre-generate a
/// key, persist it, and reuse it so a retry across process restarts replays the
/// original response rather than acting twice.
/// ```swift
/// let key = generateIdempotencyKey()
/// _ = try await client.createRedemption(.init(offer: offerID), idempotencyKey: key)
/// ```
public func generateIdempotencyKey() -> String {
  return UUID().uuidString.lowercased()
}
