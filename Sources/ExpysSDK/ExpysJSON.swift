import Foundation

/// The JSON coders every request and response goes through.
///
/// `/v1` sends timestamps as ISO 8601 strings (`2026-11-01T00:00:00.000Z`, with or
/// without fractional seconds), and the generated models type `format: date-time`
/// properties as `Date` (`MemberSummary.vipStatusAt`, `SetMemberRequest.asOf`,
/// `MemberSignalSnapshot.observedAt`...). Foundation's default coders read and write
/// a `Date` as a number, so a bare `JSONDecoder()` fails on any non-null timestamp
/// and a bare `JSONEncoder()` sends one the server rejects.
enum ExpysJSON {
  /// A decoder that reads ISO 8601 timestamps, with or without fractional seconds.
  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let text = try container.decode(String.self)
      guard let date = parseTimestamp(text) else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Expected an ISO 8601 timestamp, got \(text)")
      }
      return date
    }
    return decoder
  }

  /// An encoder that writes timestamps as ISO 8601 in UTC (`2026-11-01T00:00:00Z`).
  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(timestampFormatter(fractionalSeconds: false).string(from: date))
    }
    return encoder
  }

  private static func parseTimestamp(_ text: String) -> Date? {
    timestampFormatter(fractionalSeconds: true).date(from: text)
      ?? timestampFormatter(fractionalSeconds: false).date(from: text)
  }

  // A new formatter per use: ISO8601DateFormatter is not Sendable, and the coders'
  // strategy closures must be.
  private static func timestampFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions =
      fractionalSeconds ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
    return formatter
  }
}
