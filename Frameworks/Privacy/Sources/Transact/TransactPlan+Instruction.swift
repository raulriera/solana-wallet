import Foundation
import ModularArithmetic
import Transactions

extension TransactPlan {
    /// The circuit of a default-ring transact with Ed25519 owners, `CircuitId::ConfidentialEddsa`.
    private static let confidentialEddsaCircuit: UInt16 = 0

    /// The number of public asset slots in every transact circuit.
    private static let publicAssetSlots: UInt8 = 3

    /// Creates the transact instruction once the proof exists.
    ///
    /// The data is the tag 16, the external data's encoded prefix, the private transaction hash,
    /// the circuit (its ID as a little-endian 16-bit integer, then the input slots, the output slots,
    /// and the 3 public asset slots), the proof, each input's nullifier and tree position, and the
    /// tree contexts. The accounts are the fee payer as a writable signer, the writable output tree,
    /// the shielded-pool program, the System Program, each declared input tree in declaration order,
    /// each input's nullifier account in slot order, and for a withdrawal, the SOL interface and the
    /// recipient, all writable except the programs.
    ///
    /// - Parameters:
    ///   - proof: The proof of the plan's public inputs.
    ///   - treeContexts: One context per declared input tree, in declaration order.
    /// - Returns: The instruction, which the sender signs as the fee payer.
    /// - Throws: ``ValidationError/invalidTreeContextCount`` unless there's one context per
    ///   declared input tree, ``WincodeWriter/ValidationError/lengthOverflow`` if a count exceeds
    ///   255, or a ``Transactions/ValidationError`` if an account's derivation fails, which doesn't
    ///   happen.
    func instruction(proof: TransactProof, treeContexts: [TreeContext]) throws -> Instruction {
        guard treeContexts.count == inputTreeIDs.count else { throw ValidationError.invalidTreeContextCount }
        var writer = WincodeWriter()
        writer.append(ShieldedPool.transactTag)
        writer.append(array: externalData.encoded)
        writer.append(array: privateTransactionHash.bigEndianBytes)
        writer.append(Self.confidentialEddsaCircuit)
        writer.append(UInt8(shape.inputs))
        writer.append(UInt8(shape.outputs))
        writer.append(Self.publicAssetSlots)
        proof.write(to: &writer)
        try writer.appendCount(inputs.count)
        for input in inputs {
            writer.append(array: input.nullifier.bigEndianBytes)
            writer.append(input.treeIndex)
        }
        try writer.appendCount(treeContexts.count)
        for context in treeContexts {
            context.write(to: &writer)
        }
        let inputTrees = try inputTreeIDs.map { try ShieldedPool.tree(id: $0) }
        var accounts: [Transaction.Account] = [
            .init(address: payer, isSigner: true, isWritable: true),
            .init(address: try ShieldedPool.tree(id: outputTreeID), isSigner: false, isWritable: true),
            .init(address: try ShieldedPool.program, isSigner: false, isWritable: false),
            .init(address: try ShieldedPool.systemProgram, isSigner: false, isWritable: false),
        ]
        accounts += inputTrees.map { .init(address: $0, isSigner: false, isWritable: true) }
        accounts += try inputs.map { input in
            let tree = inputTrees[Int(input.treeIndex)]
            return .init(
                address: try ShieldedPool.nullifierAccount(tree: tree, nullifier: input.nullifier), isSigner: false, isWritable: true
            )
        }
        if let withdrawal {
            accounts += [
                .init(address: try ShieldedPool.solInterface, isSigner: false, isWritable: true),
                .init(address: withdrawal.recipient, isSigner: false, isWritable: true),
            ]
        }
        return Instruction(program: try ShieldedPool.program, accounts: accounts, data: Data(writer.bytes))
    }
}
