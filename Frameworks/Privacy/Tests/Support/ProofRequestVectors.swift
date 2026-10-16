import ModularArithmetic
@testable import Privacy
import Testing

/// The proofs of transact plans, computed by an independent Python implementation written from
/// zolana v0.4.0-alpha's sources.
///
/// The plans are those of ``InstructionVectors`` and six seeded random plans, with one or two
/// trees, transfers, withdrawals, both, and padding, all built with ``PlanFixtures``. Each plan has
/// random roots and root positions, the request body that the prover receives, and a response with
/// random curve points, alternately with and without zero padding, which reproduces the plan's
/// public input hash. Field elements are 32-byte big-endian hexadecimal.
struct ProofRequestVectors: Decodable, Sendable {
    /// The transacts.
    let transacts: [Transact]

    /// A transact plan and its proof inputs.
    struct Transact: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name, as in ``InstructionVectors``.
        let name: String
        /// The spent UTXOs, in slot order.
        let inputs: [InstructionVectors.Input]
        /// The amount for the published transfers' recipient, if any.
        let transferLamports: UInt64?
        /// The amount withdrawn to the relayed payer, if any.
        let withdrawalLamports: UInt64?
        /// The ID of the output tree.
        let outputTreeID: UInt16
        /// The number of padding inputs.
        let paddingInputs: Int
        /// The number of padding outputs.
        let paddingOutputs: Int
        /// The declared trees' slots.
        let treeSlots: [PublicInputVectors.TreeSlot]
        /// The 17 public inputs without the tree slots.
        let publicInputs: [String]
        /// The public input hash with the tree slots.
        let publicInputHash: String
        /// The request body on the prover's indexed route.
        let request: JSONValue
        /// The prover's response.
        let response: JSONValue
        /// The 192-byte proof that the instruction carries.
        let proof: String
        /// Each declared tree's UTXO and nullifier root positions.
        let treeContexts: [[UInt16]]
        /// The transact instruction's data with the proof.
        let instructionData: String

        /// The vector's name, in test results.
        var testDescription: String { name }

        /// Builds the plan.
        ///
        /// - Returns: The plan.
        /// - Throws: A test failure if a fixture is malformed, or an error if the plan can't be built.
        func plan() throws -> TransactPlan {
            try PlanFixtures.plan(
                spending: inputs.map { try PlanFixtures.utxo(lamports: $0.lamports, treeID: $0.treeID, blindingByte: $0.blindingByte) },
                transferLamports: transferLamports, withdrawal: try withdrawalLamports.map { try PlanFixtures.withdrawal(lamports: $0) },
                outputTreeID: outputTreeID, paddingInputs: paddingInputs, paddingOutputs: paddingOutputs
            )
        }
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The proof request vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "ProofRequestVectors")
    }
}
