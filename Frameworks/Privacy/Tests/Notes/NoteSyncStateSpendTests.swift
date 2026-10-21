import CryptoKit
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

/// Verifies spends of a state's notes end to end, through the real Helius client with local indexer
/// and prover responses: the selected notes, the proved instruction, the lamports that return to the
/// sender, the input slots, and the rejections before any request.
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
            /// A transfer to the published transfers' recipient, funded with a withdrawal of this
            /// many lamports to its signing address.
            case fundedRecipient(publicLamports: UInt64)
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
        /// The input slots of the proved shape, padding included.
        let nullifierCount: Int
    }

    /// The spends, with change, without change, to the sender itself, funded with a withdrawal,
    /// and with a padding input.
    static let spends = [
        Spend(
            testDescription: "transfer with change", notes: [3, 10, 5], lamports: 12, destination: .recipient, selected: [1, 2],
            receivedLamports: 3, nullifierCount: 2
        ),
        Spend(
            testDescription: "exact withdrawal", notes: [3, 10], lamports: 10, destination: .withdrawal, selected: [1], receivedLamports: 0,
            nullifierCount: 1
        ),
        Spend(
            testDescription: "transfer to the sender", notes: [10], lamports: 4, destination: .sender, selected: [0], receivedLamports: 10,
            nullifierCount: 1
        ),
        Spend(
            testDescription: "funded transfer", notes: [3, 10, 5], lamports: 6, destination: .fundedRecipient(publicLamports: 5),
            selected: [1, 2], receivedLamports: 4, nullifierCount: 2
        ),
        Spend(
            testDescription: "withdrawal with a padding input", notes: [1, 1, 1, 1, 1, 1, 1], lamports: 7, destination: .withdrawal,
            selected: [0, 1, 2, 3, 4, 5, 6], receivedLamports: 0, nullifierCount: 8
        ),
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
    /// request, and returns the instruction of a plan of those notes with the same randomness, with
    /// a nullifier count of every input slot of the plan's shape.
    ///
    /// - Parameter spend: A spend and its expected outcome.
    @Test(arguments: spends)
    func `Spends prove a plan of the selected notes`(_ spend: Spend) async throws {
        let notes = try spend.notes.enumerated().map { try note($1, leaf: UInt64($0)) }
        let state = try NoteSyncState(position: nil, notes: notes, outputTreeID: 0, pending: [], localSpends: [])
        let destination = try destination(spend.destination)
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
        #expect(result.nullifierCount == spend.nullifierCount)
        #expect(result.nullifierCount == plan.shape.inputs)
        #expect(result.inputTreeID == 0)
    }

    /// Verifies that a spend names the tree of the notes that it selects, whose fee per nullifier it
    /// pays: here the only tree whose notes cover the amount, not the tree of the first note.
    @Test
    func `Spends name the tree of their selected notes`() async throws {
        let notes = [try note(3, leaf: 0), try note(4, leaf: 1), try note(10, leaf: 2, treeID: 2)]
        let state = try NoteSyncState(position: nil, notes: notes, outputTreeID: 0, pending: [], localSpends: [])
        let destination = PrivateSpend.Destination.transfer(try TransferVectors.recipient())
        var planGenerator = SeededGenerator(seed: 7)
        let plan = try TransactPlan(
            spending: [notes[2].utxo], sender: sender, transfer: Self.transfer(destination, lamports: 9), withdrawal: nil, outputTreeID: 0,
            using: &planGenerator
        )
        let response = try Self.response(for: plan)
        let transport = StubTransport { request in
            guard request.url?.lastPathComponent == "prove" else { return try IndexerResponses.proofs(answering: request) }
            let url = try #require(request.url)
            return (response, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        }
        var spendGenerator = SeededGenerator(seed: 7)

        let result = try await state.spend(
            9, to: destination, from: sender, provider: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport),
            using: &spendGenerator
        )

        #expect(result.inputTreeID == 2)
        #expect(result.nullifiers == [notes[2].nullifier])
    }

    /// Verifies a funded transfer's transact: the recipient's note of the transfer, the sender's
    /// change of the rest of the selected notes, and a withdrawal of the funding to the recipient's
    /// signing address, which the instruction's last account and the external data hash name.
    @Test
    func `Funded transfers withdraw to the recipient's signing address`() throws {
        let recipient = try TransferVectors.recipient()
        let notes = try [10, 5].enumerated().map { try note($1, leaf: UInt64($0)) }
        var generator = SeededGenerator(seed: 7)
        let plan = try TransactPlan(
            spending: notes.map(\.utxo), sender: sender, transfer: Self.transfer(.fundedTransfer(recipient, publicLamports: 5), lamports: 6),
            withdrawal: Self.withdrawal(.fundedTransfer(recipient, publicLamports: 5), lamports: 6), outputTreeID: 0, using: &generator
        )
        let proof = try plan.proof(from: JSONDecoder().decode(TransferProofResponse.self, from: Self.response(for: plan)).proof)
        let context = TreeContext(utxoTreeRootIndex: IndexerResponses.utxoRootIndex, nullifierTreeRootIndex: IndexerResponses.nullifierRootIndex)
        let instruction = try plan.instruction(proof: proof, treeContexts: [context])
        let solInterface = try ShieldedPool.solInterface
        let senderOwner = try sender.recipient.owner
        let payerReferences = plan.outputs.filter { $0.published.ownerTag == .payer }.map { _ in sender.signingAddress.bytes }
        var expectedHash = Array(SHA256.hash(data: [ShieldedPool.transactTag] + plan.externalData.encoded
            + solInterface.bytes + recipient.signingAddress.bytes + payerReferences.flatMap(\.self)))
        expectedHash[0] = 0

        #expect(plan.withdrawal == ExternalData.Withdrawal(recipient: recipient.signingAddress, lamports: 5))
        #expect(plan.outputs.compactMap { $0.utxo?.amount } == [6, 4])
        #expect(plan.outputs.compactMap { $0.owner?.owner } == [recipient.owner, senderOwner])
        #expect(instruction.accounts.suffix(2).map(\.address) == [solInterface, recipient.signingAddress])
        #expect(plan.externalData.hash == expectedHash)
    }

    /// Verifies that a zero amount, or a funded transfer with a zero or overflowing funding
    /// withdrawal, is rejected before any request.
    ///
    /// - Parameters:
    ///   - lamports: The amount to spend from a 10-lamport note.
    ///   - destination: Where the spend goes.
    @Test(arguments: [
        (UInt64(0), Spend.Destination.recipient),
        (4, .fundedRecipient(publicLamports: 0)),
        (4, .fundedRecipient(publicLamports: .max)),
    ])
    func `Invalid amounts send no request`(lamports: UInt64, destination: Spend.Destination) async throws {
        let transport = StubTransport { _ in throw CancellationError() }
        let provider = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        let state = try NoteSyncState(position: nil, notes: [try note(10, leaf: 0)], outputTreeID: 0, pending: [], localSpends: [])
        let destination = try self.destination(destination)

        await #expect(throws: ValidationError.invalidAmount) {
            try await state.spend(lamports, to: destination, from: sender, provider: provider)
        }
        #expect(await transport.requests.isEmpty)
    }

    /// Verifies the spends that a state can't pay, rejected before any request: no output tree, an
    /// amount that only pending lamports would cover, and a funded transfer whose notes cover the
    /// transfer but not the withdrawal too.
    ///
    /// - Parameters:
    ///   - notes: The amounts of the sender's notes in tree 0, at consecutive leaves.
    ///   - outputTreeID: The state's output tree, or `nil` for none.
    ///   - pendingLamports: The lamports of the state's pending deposits.
    ///   - lamports: The amount to spend.
    ///   - destination: Where the spend goes.
    ///   - error: The expected rejection.
    @Test(arguments: [
        ([UInt64(10)], UInt16?.none, [UInt64](), UInt64(4), Spend.Destination.recipient, PrivateSpend.ValidationError.noOutputTree),
        ([], 0, [100], 50, .recipient, .insufficientFunds),
        ([10], 0, [], 6, .fundedRecipient(publicLamports: 5), .insufficientFunds),
    ])
    func `Unpayable spends send no request`(
        notes: [UInt64], outputTreeID: UInt16?, pendingLamports: [UInt64], lamports: UInt64, destination: Spend.Destination,
        error: PrivateSpend.ValidationError
    ) async throws {
        let transport = StubTransport { _ in throw CancellationError() }
        let provider = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        let state = try NoteSyncState(
            position: nil, notes: notes.enumerated().map { try note($1, leaf: UInt64($0)) }, outputTreeID: outputTreeID,
            pending: pendingLamports.map { PendingAmount(signature: IndexerResponses.signature(1), lamports: $0) }, localSpends: []
        )
        let destination = try self.destination(destination)

        await #expect(throws: error) {
            try await state.spend(lamports, to: destination, from: sender, provider: provider)
        }
        #expect(await transport.requests.isEmpty)
    }

    /// Creates a note of the sender with its real nullifier.
    ///
    /// - Parameters:
    ///   - lamports: The note's amount.
    ///   - leaf: The note's leaf index, which also sets its blinding.
    ///   - treeID: The tree that holds the note; tree 0 by default.
    /// - Returns: The note.
    /// - Throws: A test failure if a fixture is missing or malformed.
    private func note(_ lamports: UInt64, leaf: UInt64, treeID: UInt16 = 0) throws -> ReceivedNote {
        let utxo = try PlanFixtures.utxo(lamports: lamports, treeID: treeID, blindingByte: 0xa1 + UInt8(leaf))
        return ReceivedNote(
            utxo: utxo, leafIndex: leaf, signature: IndexerResponses.signature(1), slot: 1, nullifier: utxo.nullifier(using: sender.nullifierKey)
        )
    }

    /// Resolves a spend's destination.
    ///
    /// - Parameter destination: Where the spend goes.
    /// - Returns: The destination.
    /// - Throws: A test failure if a fixture is malformed.
    private func destination(_ destination: Spend.Destination) throws -> PrivateSpend.Destination {
        switch destination {
        case .recipient: .transfer(try TransferVectors.recipient())
        case .sender: .transfer(try sender.recipient)
        case .withdrawal: .withdrawal(try Address(TransferVectors.transfers[1].payer))
        case .fundedRecipient(let publicLamports): .fundedTransfer(try TransferVectors.recipient(), publicLamports: publicLamports)
        }
    }

    /// Returns a destination's transfer, if it is one.
    ///
    /// - Parameters:
    ///   - destination: The destination.
    ///   - lamports: The amount.
    /// - Returns: The transfer, or `nil` for a withdrawal.
    private static func transfer(_ destination: PrivateSpend.Destination, lamports: UInt64) -> TransactPlan.Transfer? {
        switch destination {
        case .transfer(let recipient), .fundedTransfer(let recipient, _): TransactPlan.Transfer(recipient: recipient, lamports: lamports)
        case .withdrawal: nil
        }
    }

    /// Returns a destination's withdrawal, if it is one.
    ///
    /// - Parameters:
    ///   - destination: The destination.
    ///   - lamports: The amount.
    /// - Returns: The withdrawal: the amount to the public account, or a funded transfer's funding to
    ///   its recipient's signing address; `nil` for a transfer.
    private static func withdrawal(_ destination: PrivateSpend.Destination, lamports: UInt64) -> ExternalData.Withdrawal? {
        switch destination {
        case .transfer: nil
        case .withdrawal(let address): ExternalData.Withdrawal(recipient: address, lamports: lamports)
        case .fundedTransfer(let recipient, let publicLamports): ExternalData.Withdrawal(recipient: recipient.signingAddress, lamports: publicLamports)
        }
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
