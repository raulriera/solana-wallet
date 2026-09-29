/// Controls whether a portfolio request may reuse recently retrieved data.
public enum RefreshPolicy: Sendable {
    /// Reuse data retrieved less than five minutes ago, checking holdings and prices separately.
    case ifStale
    /// Request fresh data regardless of cache age, sharing in-flight work and provider pacing.
    case reload
}
