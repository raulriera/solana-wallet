import ModularArithmetic
import Redaction

/// An amount of one asset that one owner can spend in the default ring.
struct UTXO: Sendable, Equatable, Redacted {
    static let hashDomain: UInt64 = 3

    static let dummyHashDomain: UInt64 = 1

    /// The ring hash of a UTXO without ring data or a ring program.
    private static let emptyRingHash = Poseidon.hash(.zero, .zero)

    /// The recipient's owner hash.
    let owner: Poseidon.Element

    let asset: PrivateAsset

    /// The amount, in the asset's smallest unit.
    let amount: UInt64

    let blinding: Poseidon.Element

    let treeID: UInt16

    /// The commitment that the UTXO tree holds.
    var hash: Poseidon.Element {
        Self.commitment(
            domain: Self.hashDomain, treeID: treeID, asset: asset.commitment,
            amount: Poseidon.Element(amount), owner: owner, blinding: blinding
        )
    }

    /// Returns the hash of the empty UTXO that pads an unused input or output slot of a proof.
    ///
    /// - Parameters:
    ///   - treeID: The ID of the slot's tree.
    ///   - blinding: The slot's blinding.
    /// - Returns: The empty UTXO's hash.
    static func dummyHash(treeID: UInt16, blinding: Poseidon.Element) -> Poseidon.Element {
        commitment(domain: dummyHashDomain, treeID: treeID, asset: .zero, amount: .zero, owner: .zero, blinding: blinding)
    }

    /// Derives the nullifier that spending the UTXO publishes.
    ///
    /// - Parameter key: The owner's nullifier key.
    /// - Returns: The UTXO's nullifier.
    func nullifier(using key: NullifierKey) -> Poseidon.Element {
        key.nullifier(utxoHash: hash, blinding: blinding)
    }

    /// Hashes a UTXO without data or a ring.
    ///
    /// - Parameters:
    ///   - domain: The hash's domain.
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
