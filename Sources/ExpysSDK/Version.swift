/// Embedded SDK + spec versions, surfaced in the User-Agent header for
/// server-side attribution. SDK versioning is independent semver, decoupled from
/// the spec version.
public enum ExpysVersion {
  /// This SDK's semantic version. Synced from the release tag at publish time.
  public static let sdk = "0.2.0"
  /// The OpenAPI spec version this SDK was generated against.
  public static let spec = "1.0.0"
  /// The base User-Agent (without the per-client environment/org/suffix).
  public static let userAgent = "expys-sdk-swift/\(sdk) (spec/\(spec))"

  /// Builds the per-client User-Agent, folding the environment and optional org
  /// id into the comment for server-side attribution, then appending the
  /// consumer's suffix. Format matches the TS and Kotlin SDKs:
  /// `expys-sdk-swift/<sdk> (spec/<spec>; env=<env>[; org=<org>])[ <suffix>]`.
  public static func buildUserAgent(
    environment: ExpysEnvironment,
    orgID: String?,
    suffix: String?
  ) -> String {
    var segments = ["spec/\(spec)", "env=\(environment.rawValue)"]
    if let orgID {
      segments.append("org=\(orgID)")
    }
    let base = "expys-sdk-swift/\(sdk) (\(segments.joined(separator: "; ")))"
    return suffix.map { "\(base) \($0)" } ?? base
  }
}
