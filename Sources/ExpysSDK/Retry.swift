import Foundation

private let httpDateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(identifier: "GMT")
  formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
  return formatter
}()

/// The honored Retry-After is bounded so a malformed/hostile value (e.g.
/// "99999999999999999999") can never become an unbounded sleep — or, on Swift,
/// trap the `UInt64` nanosecond conversion in the sleep closure. The server's
/// rate-limit window is 60s, so this ceiling never clips a legitimate value. The
/// three SDKs share this bound for behavioural parity.
let maxRetryAfter: TimeInterval = 300

/// Parses a Retry-After header (RFC 7231: delta-seconds or HTTP-date) into
/// seconds to wait relative to `now`. Returns nil when absent/unparseable;
/// clamps to [0, maxRetryAfter].
func parseRetryAfter(_ value: String?, now: Date) -> TimeInterval? {
  guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
    return nil
  }
  if let seconds = TimeInterval(value), value.allSatisfy({ $0.isNumber }) {
    return min(max(0, seconds), maxRetryAfter)
  }
  if let date = httpDateFormatter.date(from: value) {
    return min(max(0, date.timeIntervalSince(now)), maxRetryAfter)
  }
  return nil
}

/// Whether a status warrants a retry: 429 and any 5xx.
func isRetryableStatus(_ status: Int) -> Bool {
  return status == 429 || status >= 500
}

/// Full-jitter exponential backoff in seconds: uniformly random in
/// [0, min(cap, base * 2^attempt)]. `random` returns [0, 1) and is injectable.
func backoffDelay(
  attempt: Int,
  base: TimeInterval = 0.5,
  cap: TimeInterval = 10,
  random: () -> Double
) -> TimeInterval {
  let ceiling = min(cap, base * pow(2, Double(attempt)))
  return random() * ceiling
}
