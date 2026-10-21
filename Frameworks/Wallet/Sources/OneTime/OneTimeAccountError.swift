/// A one-time account failure that contains no secret or rejected input.
public enum OneTimeAccountError: Error, Sendable, Equatable {
    /// The code root isn't 32 bytes long.
    case invalidCodeRoot
    /// The index isn't below 2³¹, the hardened derivation range.
    case invalidIndex
    /// The secret isn't 32 bytes long.
    case invalidSecret
}
