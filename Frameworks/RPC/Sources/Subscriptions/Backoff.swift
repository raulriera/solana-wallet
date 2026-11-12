/// A wait that doubles after each attempt, up to a longest wait, and starts over after a success.
public struct Backoff: Sendable {
    /// Two seconds, doubling up to a minute.
    public static let reconnection = Backoff(first: .seconds(2), longest: .seconds(60))

    private let first: Duration
    private let longest: Duration
    private var delay: Duration

    /// Creates a backoff.
    ///
    /// - Parameters:
    ///   - first: The wait before the first attempt and after each success.
    ///   - longest: The longest wait.
    public init(first: Duration, longest: Duration) {
        self.first = first
        self.longest = longest
        delay = first
    }

    /// Returns the wait before the next attempt and doubles the one after, up to the longest.
    ///
    /// - Returns: The wait before the next attempt.
    public mutating func next() -> Duration {
        defer { delay = min(delay * 2, longest) }
        return delay
    }

    /// Starts over from the first wait.
    public mutating func reset() {
        delay = first
    }
}
