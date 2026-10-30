/// An error for an invalid private-note request or proof value.
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
    /// A proof read asks for more than 1,000 leaves.
    case tooManyLeaves
    /// A proof's value isn't 32 bytes, or its path doesn't have its tree's height.
    case invalidProof
}
