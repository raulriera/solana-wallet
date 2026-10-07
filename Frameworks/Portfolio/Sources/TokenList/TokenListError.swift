/// A reason an account's token list can't change or load.
public enum TokenListError: Error, Equatable {
    /// The list already holds the most tokens a person can add.
    case limitReached
    /// A saved list exists but can't be read; it stays in place instead of being replaced with the defaults.
    case unreadable
}
