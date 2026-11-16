import ModularArithmetic
import Testing
@testable import Privacy

struct ProofRequestVectors: Decodable, Sendable {
    let transacts: [Transact]

    struct Transact: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let inputs: [InstructionVectors.Input]
        let transferLamports: UInt64?
        let withdrawalLamports: UInt64?
        let outputTreeID: UInt16
        let paddingInputs: Int
        let paddingOutputs: Int
        let treeSlots: [PublicInputVectors.TreeSlot]
        let publicInputs: [String]
        let publicInputHash: String
        let merkleProofs: [[JSONValue]]
        let request: JSONValue
        let response: JSONValue
        let proof: String
        let treeContexts: [[UInt16]]
        let instructionData: String

        var testDescription: String { name }

        func plan() throws -> TransactPlan {
            try PlanFixtures.plan(
                spending: inputs.map { try PlanFixtures.utxo(amount: $0.lamports, treeID: $0.treeID, blindingByte: $0.blindingByte, asset: .nativeSOL) },
                transferLamports: transferLamports, withdrawal: try withdrawalLamports.map { try PlanFixtures.withdrawal(lamports: $0) },
                outputTreeID: outputTreeID, paddingInputs: paddingInputs, paddingOutputs: paddingOutputs
            )
        }
    }

    static func load() throws -> Self {
        try fixture(named: "ProofRequestVectors")
    }
}
