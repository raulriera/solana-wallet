/// A private-note request that the provider refuses before networking, or a proof value that it can't hold.
public enum PrivateNoteError: Error, Sendable, Equatable {
    /// A view tag isn't 32 bytes.
    case invalidTag
    /// A nullifier isn't 32 bytes.
    case invalidNullifier
    /// The position came from a read of a different number of view tags.
    case mismatchedPosition
    /// A UTXO hash isn't 32 bytes.
    case invalidLeaf
    /// A tree account isn't 32 bytes of base 58.
    case invalidTree
    /// A proof read asks for more than the 1,000 leaves that one request holds.
    case tooManyLeaves
    /// A proof's value isn't 32 bytes, or its path doesn't have its tree's height.
    case invalidProof
}
