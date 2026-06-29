import Foundation

/// Org-API-Key machine credentials are formatted `expys_<env>_<random>` (e.g.
/// `expys_live_...`, `expys_sandbox_...`). A member token is a PASETO
/// `v4.local.…` and never starts with `expys_`.
private let machineCredentialPrefix = "expys_"

/// Classifies a configured credential as a machine (Org-API-Key) credential. True
/// iff the token starts with `expys_`. Machine credentials are long-lived and not
/// refreshed, so the initially configured token is authoritative.
func isMachineCredential(_ token: String) -> Bool {
  token.hasPrefix(machineCredentialPrefix)
}

/// Fails fast, client-side, when a server-only method is called without a machine
/// credential (i.e. a member token was supplied). Throws ``ExpysError/notConfigured(_:)``
/// before any network call. The server also enforces this (a member token gets 403
/// via the route auth matrix), but the SDK rejects it without a round-trip.
func assertMachineCredential(_ token: String, method: String) throws {
  guard isMachineCredential(token) else {
    throw ExpysError.notConfigured(
      "`\(method)` is a server-only method and requires an Org-API-Key credential, "
        + "not a member token. "
        + "Never embed an Org-API-Key in a client app."
    )
  }
}
