/// A private-note request that the provider refuses before networking.
public enum PrivateNoteError: Error, Sendable, Equatable {
    /// A view tag isn't 32 bytes.
    case invalidTag
    /// A nullifier isn't 32 bytes.
    case invalidNullifier
    /// The position came from a read of a different number of view tags.
    case mismatchedPosition
}
