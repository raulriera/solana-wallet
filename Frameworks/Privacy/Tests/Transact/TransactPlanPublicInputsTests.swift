import ModularArithmetic
import Testing
import Transactions
@testable import Privacy

struct TransactPlanPublicInputsTests {
    @Test(arguments: try ProofRequestVectors.load().transacts)
    func `Statements match the independent reference`(_ vector: ProofRequestVectors.Transact) throws {
        let publicInputs = try vector.plan().publicInputs

        let hash = publicInputs.hash(treeSlots: try vector.treeSlots.map { try $0.slot() })

        #expect(publicInputs.elements.map(\.bigEndianBytes) == (try vector.publicInputs.map(fixtureBytes)))
        #expect(hash.bigEndianBytes == (try fixtureBytes(vector.publicInputHash)))
    }

    @Test
    func `Padding slots take the identity of their view tag`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(amount: 10, asset: .nativeSOL)], of: .nativeSOL, transfer: 10, paddingOutputs: 1)
        let recipient = OwnerIdentity.solana(signingPublicKey: try TransferVectors.recipient().viewTag)

        #expect(plan.outputOwnerIdentities == [recipient, recipient])
    }

    @Test
    func `Withdrawals fill the first public slot`() throws {
        let plan = try PlanFixtures.plan(
            spending: [PlanFixtures.utxo(amount: 10, asset: .nativeSOL)], of: .nativeSOL, transfer: nil, withdrawal: PlanFixtures.withdrawal(10, of: .nativeSOL), paddingOutputs: 1
        )

        #expect(plan.publicInputs.publicAssets == [Poseidon.hash(.zero, .zero), .zero, .zero])
        #expect(plan.publicInputs.publicAmounts == [
            try Poseidon.Element(hex: "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593effffff7"), .zero, .zero,
        ])
    }
}
