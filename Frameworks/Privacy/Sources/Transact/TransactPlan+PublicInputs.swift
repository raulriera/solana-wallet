import ModularArithmetic
import Transactions

extension TransactPlan {
    /// The statement that the plan's proof commits to, without the tree roots.
    var publicInputs: PublicInputs {
        let unusedSlots = Array(repeating: Poseidon.Element.zero, count: PublicInputs.publicSlotCount - 1)
        let signers = [OwnerIdentity.solana(signingPublicKey: payer.bytes)]
            + Array(repeating: .zero, count: shape.signerWidth - 1)
        return PublicInputs(
            nullifiers: nullifiers,
            outputHashes: commitments,
            outputTreeID: outputTreeID,
            privateTransactionHash: privateTransactionHash,
            externalDataHash: Poseidon.Element(reducing: externalData.hash),
            publicAssets: [withdrawal?.asset.commitment ?? .zero] + unusedSlots,
            publicAmounts: [withdrawal.map { -Poseidon.Element($0.amount) } ?? .zero] + unusedSlots,
            ringProgramID: .zero,
            signerIdentities: signers,
            inputFlags: InputFlags.pack(treeIndexes: inputs.map(\.treeIndex)),
            outputOwnerIdentities: outputOwnerIdentities,
            cacheTreeID: .zero,
            cacheReadHashChain: HashChain.zeroSuffix(groups: (shape.inputs - 1 + 2) / 3)
        )
    }

    /// The Solana identity of each output slot's view tag, in slot order.
    var outputOwnerIdentities: [Poseidon.Element] {
        outputs.map { output in
            switch output.published.ownerTag {
            case .inline(let viewTag): OwnerIdentity.solana(signingPublicKey: viewTag)
            case .payer: OwnerIdentity.solana(signingPublicKey: payer.bytes)
            }
        }
    }
}
