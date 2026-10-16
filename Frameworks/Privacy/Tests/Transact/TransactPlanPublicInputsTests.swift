import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

/// Verifies the statements of transact plans against an independent implementation.
struct TransactPlanPublicInputsTests {
    /// Verifies each plan's 17 public inputs and its hash with the fixture's tree roots: transfers,
    /// withdrawals, two input trees, and padding inputs and outputs.
    ///
    /// - Parameter vector: A plan and its proof inputs.
    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Statements match the independent reference`(_ vector: ProofRequestVectors.Transact) throws {
        let publicInputs = try vector.plan().publicInputs

        let hash = publicInputs.hash(treeSlots: try vector.treeSlots.map { try $0.slot() })

        #expect(publicInputs.elements.map(\.bigEndianBytes) == (try vector.publicInputs.map(fixtureBytes)))
        #expect(hash.bigEndianBytes == (try fixtureBytes(vector.publicInputHash)))
    }

    /// Verifies the owner identities of a transfer without change: the recipient's slot and the
    /// padding slot that carries the recipient's view tag.
    @Test
    func `Padding slots take the identity of their view tag`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 10, paddingOutputs: 1)
        let recipient = OwnerIdentity.solana(signingPublicKey: try TransferVectors.recipient().viewTag)

        #expect(plan.outputOwnerIdentities == [recipient, recipient])
    }

    /// Verifies the public slots of a withdrawal: SOL's asset commitment and r - 10 in slot 0, and
    /// zeros in the other slots.
    @Test
    func `Withdrawals fill the first public slot`() throws {
        let plan = try PlanFixtures.plan(
            spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: nil, withdrawal: PlanFixtures.withdrawal(lamports: 10), paddingOutputs: 1
        )

        #expect(plan.publicInputs.publicAssets == [Poseidon.hash(.zero, .zero), .zero, .zero])
        #expect(plan.publicInputs.publicAmounts == [
            try Poseidon.Element(hex: "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593effffff7"), .zero, .zero,
        ])
    }
}
