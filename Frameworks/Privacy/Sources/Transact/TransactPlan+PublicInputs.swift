import ModularArithmetic
import Transactions

extension TransactPlan {
    /// The statement that the plan's proof commits to, without the tree roots, which come from the
    /// indexer's proofs.
    ///
    /// The sender owns every input and pays the fee, so the signer identities are the payer's,
    /// then zeros up to the shape's signer width. A withdrawal fills public slot 0 with SOL's asset
    /// commitment, `Poseidon(0, 0)`, and `r - lamports`; the other slots are zero. The ring program
    /// and the cache's tree are zero, and without a cache, the read chain is the chain of zeros
    /// that covers the inputs after the first, `Z(⌈(inputs - 1) / 3⌉)`.
    var publicInputs: PublicInputs {
        let solAsset = PackedBytes.hash32(ConfidentialPlaintext.Asset.sol.mint)
        let unusedSlots = Array(repeating: Poseidon.Element.zero, count: PublicInputs.publicSlotCount - 1)
        let signers = [OwnerIdentity.solana(signingPublicKey: payer.bytes)]
            + Array(repeating: .zero, count: shape.signerWidth - 1)
        return PublicInputs(
            nullifiers: nullifiers,
            outputHashes: commitments,
            outputTreeID: outputTreeID,
            privateTransactionHash: privateTransactionHash,
            externalDataHash: Poseidon.Element(reducing: externalData.hash),
            publicAssets: [withdrawal == nil ? .zero : solAsset] + unusedSlots,
            publicAmounts: [withdrawal.map { -Poseidon.Element($0.lamports) } ?? .zero] + unusedSlots,
            ringProgramID: .zero,
            signerIdentities: signers,
            inputFlags: InputFlags.pack(treeIndexes: inputs.map(\.treeIndex)),
            outputOwnerIdentities: outputOwnerIdentities,
            cacheTreeID: .zero,
            cacheReadHashChain: HashChain.zeroSuffix(groups: (shape.inputs - 1 + 2) / 3)
        )
    }

    /// The Solana identity of each output slot's view tag, in slot order: the owner's signing
    /// address, or the padding view tag for a padding slot.
    ///
    /// The proof binds each published owner tag to these identities, and the circuit requires
    /// every padding slot's tag to name a real output's owner.
    var outputOwnerIdentities: [Poseidon.Element] {
        outputs.map { output in
            switch output.published.ownerTag {
            case .inline(let viewTag): OwnerIdentity.solana(signingPublicKey: viewTag)
            case .payer: OwnerIdentity.solana(signingPublicKey: payer.bytes)
            }
        }
    }
}
