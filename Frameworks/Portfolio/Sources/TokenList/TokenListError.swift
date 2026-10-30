/// An error from changing or loading an account's token list.
public enum TokenListError: Error, Equatable {
    case limitReached
    /// A saved list exists but can't be read.
    case unreadable
}
