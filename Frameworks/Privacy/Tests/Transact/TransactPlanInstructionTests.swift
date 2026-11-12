import Foundation
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy

struct TransactPlanInstructionTests {
    @Test(arguments: try InstructionVectors.load().transacts)
    func `Transacts match the independent reference`(_ vector: InstructionVectors.Transact) throws {
        let utxos = try vector.inputs.map {
            try PlanFixtures.utxo(lamports: $0.lamports, treeID: $0.treeID, blindingByte: $0.blindingByte)
        }
        let plan = try PlanFixtures.plan(
            spending: utxos, transferLamports: vector.transferLamports,
            withdrawal: try vector.withdrawalLamports.map { try PlanFixtures.withdrawal(lamports: $0) },
            outputTreeID: vector.outputTreeID, paddingInputs: vector.paddingInputs, paddingOutputs: vector.paddingOutputs
        )
        let proof = try TransactProof(a: Array(repeating: 1, count: 32), b: Array(repeating: 2, count: 128), c: Array(repeating: 3, count: 32))
        let contexts = vector.treeContexts.map { TreeContext(utxoTreeRootIndex: $0[0], nullifierTreeRootIndex: $0[1]) }

        let instruction = try plan.instruction(proof: proof, treeContexts: contexts)

        #expect(plan.externalData.hash == (try fixtureBytes(vector.externalDataHash)))
        #expect(plan.privateTransactionHash.bigEndianBytes == (try fixtureBytes(vector.privateTransactionHash)))
        #expect(instruction.program == (try Address(InstructionVectors.load().program)))
        #expect(Array(instruction.data) == (try fixtureBytes(vector.data)))
        #expect(instruction.accounts == (try vector.accounts.map { try $0.account() }))
    }

    @Test(arguments: [0, 2])
    func `Instructions need one tree context per input tree`(count: Int) throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let proof = try TransactProof(a: Array(repeating: 0, count: 32), b: Array(repeating: 0, count: 128), c: Array(repeating: 0, count: 32))
        let contexts = Array(repeating: TreeContext(utxoTreeRootIndex: 0, nullifierTreeRootIndex: 0), count: count)

        #expect(throws: TransactPlan.ValidationError.invalidTreeContextCount) {
            try plan.instruction(proof: proof, treeContexts: contexts)
        }
    }
}
