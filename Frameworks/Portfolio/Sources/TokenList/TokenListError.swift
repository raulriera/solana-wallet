/// An error from changing or loading an account's token list.
public enum TokenListError: Error, Equatable {
    case limitReached
    /// The file of a saved list can't be read.
    case unreadable
}
