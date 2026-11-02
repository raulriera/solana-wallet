/// An error for an invalid private-note request.
public enum PrivateNoteError: Error, Sendable, Equatable {
    /// A view tag isn't 32 bytes.
    case invalidTag
    /// A nullifier isn't 32 bytes.
    case invalidNullifier
    /// The position came from a read of other view tags.
    case mismatchedPosition
    /// A UTXO hash isn't 32 bytes.
    case invalidLeaf
    /// A tree account isn't 32 bytes of base 58.
    case invalidTree
}
