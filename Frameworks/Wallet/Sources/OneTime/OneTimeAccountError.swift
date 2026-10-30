/// An error from creating a one-time account.
public enum OneTimeAccountError: Error, Sendable, Equatable {
    /// The code root isn't 32 bytes long.
    case invalidCodeRoot
    /// The index isn't below 2³¹.
    case invalidIndex
    /// The secret isn't 32 bytes long.
    case invalidSecret
}
