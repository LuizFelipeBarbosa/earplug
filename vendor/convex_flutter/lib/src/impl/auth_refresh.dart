const Duration _minimumRefreshDelay = Duration(seconds: 30);
const Duration _longLivedRefreshLeadTime = Duration(seconds: 60);
const Duration _longLivedTokenThreshold = Duration(minutes: 4);

/// Returns the delay before refreshing a token that expires at [expiry].
///
/// Expired tokens wait 30 seconds to avoid a hot loop. Tokens with at least
/// four minutes remaining refresh one minute before expiry. Short-lived tokens
/// refresh after 75% of their remaining lifetime, with the same 30-second floor
/// so unusual token lifetimes do not cause rapid repeated refreshes.
Duration authRefreshDelay({required DateTime expiry, required DateTime now}) {
  final remaining = expiry.difference(now);
  if (remaining <= Duration.zero) {
    return _minimumRefreshDelay;
  }
  if (remaining >= _longLivedTokenThreshold) {
    return remaining - _longLivedRefreshLeadTime;
  }

  final fractionalDelay = remaining * 0.75;
  return fractionalDelay > _minimumRefreshDelay
      ? fractionalDelay
      : _minimumRefreshDelay;
}

/// Returns an exponentially increasing reconnect delay with bounded jitter.
///
/// The base delay doubles from one second and is capped at 30 seconds before
/// [jitterFactor] is applied. The factor must be between 0.8 and 1.2, inclusive,
/// so a capped delay may range from 24 to 36 seconds. Callers can supply random
/// factors in that range, while tests can use a deterministic value.
Duration reconnectDelay(int attempt, {double jitterFactor = 1.0}) {
  if (attempt < 0) {
    throw ArgumentError.value(attempt, 'attempt', 'must not be negative');
  }
  if (!jitterFactor.isFinite || jitterFactor < 0.8 || jitterFactor > 1.2) {
    throw ArgumentError.value(
      jitterFactor,
      'jitterFactor',
      'must be between 0.8 and 1.2',
    );
  }

  final baseSeconds = attempt >= 5 ? 30 : 1 << attempt;
  return Duration(seconds: baseSeconds) * jitterFactor;
}
