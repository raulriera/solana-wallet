/// The proof-input identity of a Solana owner and the owner hash that commits to it.
enum OwnerIdentity {
    /// The algorithm tag of a Solana owner, ASCII S.
    private static let solanaTag: UInt8 = 0x53

    /// Returns the identity of a Solana owner.
    ///
    /// - Parameter signingPublicKey: The owner's 32-byte Ed25519 public key.
    /// - Returns: The commitment to the Solana tag followed by `signingPublicKey`.
    static func solana(signingPublicKey: [UInt8]) -> Poseidon.Element {
        precondition(signingPublicKey.count == 32, "An Ed25519 public key needs exactly 32 bytes.")
        return PackedBytes.hash33([solanaTag] + signingPublicKey)
    }

    /// Returns the owner hash of a Solana owner.
    ///
    /// - Parameters:
    ///   - signingPublicKey: The owner's 32-byte Ed25519 public key.
    ///   - nullifierPublicKey: The public key of the owner's ``NullifierKey``.
    /// - Returns: `Poseidon(identity, nullifierPublicKey)`.
    static func ownerHash(signingPublicKey: [UInt8], nullifierPublicKey: Poseidon.Element) -> Poseidon.Element {
        Poseidon.hash(solana(signingPublicKey: signingPublicKey), nullifierPublicKey)
    }
}
