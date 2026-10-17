import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

/// Verifies spends of a state's notes end to end, through the real Helius client with local indexer
/// and prover responses: the selected notes, the proved instruction, the lamports that return to the
/// sender, and the rejections before any request.
///
/// Each expected instruction comes from a plan of the expected notes with the same seeded
/// randomness, and the indexer's fixed proofs give its trees fixed root positions.
struct NoteSyncStateSpendTests {
    /// A spend and its expected outcome.
    struct Spend: Sendable, CustomTestStringConvertible {
        /// Where the spend goes.
        enum Destination: Sendable {
            /// A transfer to the published transfers' recipient.
            case recipient
            /// A transfer to the sender's own shielded address.
            case sender
            /// A withdrawal to the published relayed payer.
            case withdrawal
        }

        /// The spend's name, in test results.
        let testDescription: String
        /// The amounts of the sender's notes in tree 0, at consecutive leaves.
        let notes: [UInt64]
        /// The amount to spend.
        let lamports: UInt64
        /// Where the spend goes.
        let destination: Destination
        /// The leaves of the notes that the spend selects, in input order.
        let selected: [Int]
        /// The lamports of the outputs that the sender owns.
        let receivedLamports: UInt64
    }

    /// The spends, with change, without change, and to the sender itself.
    static let spends = [
        Spend(testDescription: "transfer with change", notes: [3, 10, 5], lamports: 12, destination: .recipient, selected: [1, 2], receivedLamports: 3),
        Spend(testDescription: "exact withdrawal", notes: [3, 10], lamports: 10, destination: .withdrawal, selected: [1], receivedLamports: 0),
        Spend(testDescription: "transfer to the sender", notes: [10], lamports: 4, destination: .sender, selected: [0], receivedLamports: 10),
    ]

    /// The sender of zolana's published transfers.
    private let sender: ShieldedAccount

    /// Loads the sender.
    ///
    /// - Throws: A test failure if the fixture is missing or malformed.
    init() throws {
        sender = try TransferVectors.sender()
    }

    /// Verifies that a spend selects the expected notes, reads the tree's proofs, sends one proof
    /// request, and returns the instruction of a plan of those notes with the same randomness.
    ///
    /// - Parameter spend: A spend and its expected outcome.
    @Test(arguments: spends)
    func `Spends prove a plan of the selected notes`(_ spend: Spend) async throws {
        let notes = try spend.notes.enumerated().map { try note($1, leaf: UInt64($0)) }
        let state = try NoteSyncState(position: nil, notes: notes, outputTreeID: 0, pending: [], localSpends: [])
        let destination = try destination(of: spend)
        let selected = spend.selected.map { notes[$0] }
        var planGenerator = SeededGenerator(seed: 7)
        let plan = try TransactPlan(
            spending: selected.map(\.utxo), sender: sender, transfer: Self.transfer(destination, lamports: spend.lamports),
            withdrawal: Self.withdrawal(destination, lamports: spend.lamports), outputTreeID: 0, using: &planGenerator
        )
        let response = try Self.response(for: plan)
        let proof = try plan.proof(from: JSONDecoder().decode(TransferProofResponse.self, from: response).proof)
        let context = TreeContext(utxoTreeRootIndex: IndexerResponses.utxoRootIndex, nullifierTreeRootIndex: IndexerResponses.nullifierRootIndex)
        let transport = StubTransport { request in
            guard request.url?.lastPathComponent == "prove" else { return try IndexerResponses.proofs(answering: request) }
            let url = try #require(request.url)
            return (response, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        }
        var spendGenerator = SeededGenerator(seed: 7)

        let result = try await state.spend(
            spend.lamports, to: destination, from: sender, provider: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport),
            using: &spendGenerator
        )

        let routes = await transport.requests.compactMap { $0.url?.lastPathComponent }
        #expect(routes.sorted() == [GetMerkleProofs.method, GetNonInclusionProofs.method, "prove"])
        #expect(result.instruction == (try plan.instruction(proof: proof, treeContexts: [context])))
        #expect(result.nullifiers == selected.map(\.nullifier))
        #expect(result.lamports == spend.lamports)
        #expect(result.receivedLamports == spend.receivedLamports)
    }

    /// Verifies the rejections before any proof request: no output tree, zero lamports, and an
    /// amount that only pending lamports would cover.
    @Test
    func `Invalid spends send no request`() async throws {
        let transport = StubTransport { _ in throw CancellationError() }
        let provider = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        let notes = [try note(10, leaf: 0)]
        let untreed = try NoteSyncState(position: nil, notes: notes, outputTreeID: nil, pending: [], localSpends: [])
        let funded = try NoteSyncState(position: nil, notes: notes, outputTreeID: 0, pending: [], localSpends: [])
        let pending = try NoteSyncState(
            position: nil, notes: [], outputTreeID: 0, pending: [PendingAmount(signature: IndexerResponses.signature(1), lamports: 100)],
            localSpends: []
        )
        let destination = PrivateSpend.Destination.transfer(try TransferVectors.recipient())

        await #expect(throws: PrivateSpend.ValidationError.noOutputTree) {
            try await untreed.spend(4, to: destination, from: sender, provider: provider)
        }
        await #expect(throws: ValidationError.invalidAmount) {
            try await funded.spend(0, to: destination, from: sender, provider: provider)
        }
        await #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try await pending.spend(50, to: destination, from: sender, provider: provider)
        }
        #expect(await transport.requests.isEmpty)
    }

    /// Creates a note of the sender in tree 0 with its real nullifier.
    ///
    /// - Parameters:
    ///   - lamports: The note's amount.
    ///   - leaf: The note's leaf index, which also sets its blinding.
    /// - Returns: The note.
    /// - Throws: A test failure if a fixture is missing or malformed.
    private func note(_ lamports: UInt64, leaf: UInt64) throws -> ReceivedNote {
        let utxo = try PlanFixtures.utxo(lamports: lamports, blindingByte: 0xa1 + UInt8(leaf))
        return ReceivedNote(
            utxo: utxo, leafIndex: leaf, signature: IndexerResponses.signature(1), slot: 1, nullifier: utxo.nullifier(using: sender.nullifierKey)
        )
    }

    /// Resolves a spend's destination.
    ///
    /// - Parameter spend: The spend.
    /// - Returns: The destination.
    /// - Throws: A test failure if a fixture is malformed.
    private func destination(of spend: Spend) throws -> PrivateSpend.Destination {
        switch spend.destination {
        case .recipient: .transfer(try TransferVectors.recipient())
        case .sender: .transfer(try sender.recipient)
        case .withdrawal: .withdrawal(try Address(TransferVectors.transfers[1].payer))
        }
    }

    /// Returns a destination's transfer, if it is one.
    ///
    /// - Parameters:
    ///   - destination: The destination.
    ///   - lamports: The amount.
    /// - Returns: The transfer, or `nil` for a withdrawal.
    private static func transfer(_ destination: PrivateSpend.Destination, lamports: UInt64) -> TransactPlan.Transfer? {
        guard case .transfer(let recipient) = destination else { return nil }
        return TransactPlan.Transfer(recipient: recipient, lamports: lamports)
    }

    /// Returns a destination's withdrawal, if it is one.
    ///
    /// - Parameters:
    ///   - destination: The destination.
    ///   - lamports: The amount.
    /// - Returns: The withdrawal, or `nil` for a transfer.
    private static func withdrawal(_ destination: PrivateSpend.Destination, lamports: UInt64) -> ExternalData.Withdrawal? {
        guard case .withdrawal(let address) = destination else { return nil }
        return ExternalData.Withdrawal(recipient: address, lamports: lamports)
    }

    /// Creates the prover's response for a plan: the first proof vector's curve points and the plan's
    /// proving key.
    ///
    /// - Parameter plan: The plan.
    /// - Returns: The response body.
    /// - Throws: A test failure if a fixture is missing or malformed.
    private static func response(for plan: TransactPlan) throws -> Data {
        let vector = try #require(try ProofRequestVectors.load().transacts.first)
        var fields = try JSONDecoder().decode([String: JSONValue].self, from: vector.response.data)
        fields["provingKeySha256"] = .string(hex(plan.shape.provingKeyDigest))
        return try JSONValue.object(fields).data
    }

    /// Encodes bytes as lowercase hexadecimal.
    ///
    /// - Parameter bytes: The bytes.
    /// - Returns: Two digits per byte.
    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
