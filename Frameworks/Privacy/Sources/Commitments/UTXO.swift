import ModularArithmetic

/// A Solana Rings UTXO in the default ring: an amount of one asset that one owner can spend.
///
/// Peer-to-peer transfers in the default ring carry no UTXO data, ring data, or ring program, so
/// the data hash is zero and the ring hash is `Poseidon(0, 0)`. The UTXO's hash is
/// `Poseidon(3, tree ID, hash_bytes_32(mint), amount, 0, Poseidon(0, 0), Poseidon(owner, blinding))`,
/// with the domain 3, the tree ID, and the amount as integers. The UTXO tree appends the hash
/// when the UTXO is created. Descriptions and reflection omit the amount and the blinding, which a
/// received UTXO takes from its decrypted note.
struct UTXO: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The domain of a UTXO's hash.
    private static let hashDomain: UInt64 = 3

    /// The domain of an empty UTXO's hash.
    private static let dummyHashDomain: UInt64 = 1

    /// The ring hash of a UTXO without ring data or a ring program, `Poseidon(0, 0)`.
    private static let emptyRingHash = Poseidon.hash(.zero, .zero)

    /// The recipient's owner hash, from their shielded address.
    let owner: Poseidon.Element

    /// The asset's 32-byte mint address; SOL's is 32 zero bytes.
    let mint: [UInt8]

    /// The amount, in the asset's smallest unit.
    let amount: UInt64

    /// The value that keeps UTXOs with the same owner, asset, and amount apart, such as a transact
    /// output's blinding.
    let blinding: Poseidon.Element

    /// The ID of the tree that holds the UTXO.
    let treeID: UInt16

    /// A description that omits the amount and the blinding.
    var description: String { "UTXO" }

    /// A debugging description that omits the amount and the blinding.
    var debugDescription: String { description }

    /// A reflection view that omits the amount and the blinding.
    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// The commitment that the UTXO tree holds.
    ///
    /// - Precondition: ``mint`` contains exactly 32 bytes.
    var hash: Poseidon.Element {
        Self.commitment(
            domain: Self.hashDomain, treeID: treeID, asset: PackedBytes.hash32(mint),
            amount: Poseidon.Element(amount), owner: owner, blinding: blinding
        )
    }

    /// Returns the hash of the empty UTXO that pads an unused input or output slot of a proof.
    ///
    /// The empty UTXO has the domain 1, and its owner, asset, and amount are zero. Its asset is zero,
    /// not the hash of SOL's zero mint. No one can spend it, because no key has a zero owner hash.
    ///
    /// - Parameters:
    ///   - treeID: The ID of the slot's tree: the input's tree, or the output tree.
    ///   - blinding: The slot's blinding: random for an input, or the slot's output blinding.
    /// - Returns: `Poseidon(1, treeID, 0, 0, 0, Poseidon(0, 0), Poseidon(0, blinding))`.
    static func dummyHash(treeID: UInt16, blinding: Poseidon.Element) -> Poseidon.Element {
        commitment(domain: dummyHashDomain, treeID: treeID, asset: .zero, amount: .zero, owner: .zero, blinding: blinding)
    }

    /// Derives the nullifier that spending the UTXO publishes.
    ///
    /// - Parameter key: The owner's nullifier key, whose public key is part of ``owner``.
    /// - Returns: The nullifier of ``hash`` and ``blinding``.
    /// - Precondition: ``mint`` contains exactly 32 bytes.
    func nullifier(using key: NullifierKey) -> Poseidon.Element {
        key.nullifier(utxoHash: hash, blinding: blinding)
    }

    /// Hashes a UTXO without data or a ring.
    ///
    /// - Parameters:
    ///   - domain: The domain, 3 for a UTXO or 1 for an empty UTXO.
    ///   - treeID: The ID of the tree that holds the UTXO.
    ///   - asset: The commitment to the asset.
    ///   - amount: The amount.
    ///   - owner: The owner hash.
    ///   - blinding: The blinding.
    /// - Returns: The UTXO's hash.
    private static func commitment(
        domain: UInt64,
        treeID: UInt16,
        asset: Poseidon.Element,
        amount: Poseidon.Element,
        owner: Poseidon.Element,
        blinding: Poseidon.Element
    ) -> Poseidon.Element {
        Poseidon.hash(
            Poseidon.Element(domain), Poseidon.Element(UInt64(treeID)), asset, amount,
            .zero, emptyRingHash, Poseidon.hash(owner, blinding)
        )
    }
}
