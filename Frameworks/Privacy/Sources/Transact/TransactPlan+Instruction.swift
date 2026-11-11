import Foundation
import ModularArithmetic
import Transactions

extension TransactPlan {
    /// The circuit ID of a transact that its owners sign.
    static let confidentialSignerCircuit: UInt16 = 0

    private static let publicAssetSlots: UInt8 = 3

    /// Creates the transact instruction from the plan's proof.
    ///
    /// - Parameters:
    ///   - proof: The proof of the plan's public inputs.
    ///   - treeContexts: One context per declared input tree, in declaration order.
    /// - Returns: The transact instruction.
    /// - Throws: ``ValidationError/invalidTreeContextCount`` unless there's one context per
    ///   declared input tree, ``WincodeWriter/ValidationError/lengthOverflow`` if a count exceeds
    ///   255, or a ``Transactions/ValidationError`` if an account's derivation fails.
    func instruction(proof: TransactProof, treeContexts: [TreeContext]) throws -> Instruction {
        guard treeContexts.count == inputTreeIDs.count else { throw ValidationError.invalidTreeContextCount }
        var writer = WincodeWriter()
        writer.append(ShieldedPool.transactTag)
        writer.append(array: externalData.encoded)
        writer.append(array: privateTransactionHash.bigEndianBytes)
        writer.append(Self.confidentialSignerCircuit)
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
            .writable(payer, isSigner: true),
            .writable(try ShieldedPool.tree(id: outputTreeID)),
            .readonly(try ShieldedPool.program),
            .readonly(try SystemProgram.address),
        ]
        accounts += inputTrees.map { .writable($0) }
        accounts += try inputs.map { input in
            let tree = inputTrees[Int(input.treeIndex)]
            return .writable(try ShieldedPool.nullifierAccount(tree: tree, nullifier: input.nullifier))
        }
        accounts.append(.readonly(payer, isSigner: true))
        if let withdrawal { accounts += try withdrawal.settlementAccounts }
        return Instruction(program: try ShieldedPool.program, accounts: accounts, data: Data(writer.bytes))
    }
}
