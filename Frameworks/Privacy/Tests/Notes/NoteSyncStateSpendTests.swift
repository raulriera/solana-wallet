import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

struct NoteSyncStateSpendTests {
    struct Spend: Sendable, CustomTestStringConvertible {
        enum Destination: Sendable {
            case recipient
            case sender
            case withdrawal
            case fundedRecipient(publicLamports: UInt64)
        }

        let testDescription: String
        let notes: [UInt64]
        let lamports: UInt64
        let destination: Destination
        let selected: [Int]
        let receivedLamports: UInt64
        let nullifierCount: Int
    }

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

    private let sender: ShieldedAccount

    init() throws {
        sender = try TransferVectors.sender()
    }

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
        let response = try Self.response(for: plan.shape)
        let proof = try plan.proof(from: JSONDecoder().decode(TransferProofResponse.self, from: response).proof)
        let context = TreeContext(utxoTreeRootIndex: IndexerResponses.utxoRootIndex, nullifierTreeRootIndex: IndexerResponses.nullifierRootIndex)
        let transport = StubTransport { request in
            guard request.url?.lastPathComponent == "prove" else { return try IndexerResponses.spendReads(answering: request) }
            let url = try #require(request.url)
            return (response, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        }
        var spendGenerator = SeededGenerator(seed: 7)

        let result = try await state.spend(
            spend.lamports, to: destination, from: sender, provider: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport),
            using: &spendGenerator
        )

        let routes = await transport.requests.compactMap { $0.url?.lastPathComponent }
        #expect(routes.sorted() == ["/", GetMerkleProofs.method, GetNonInclusionProofs.method, "prove"])
        #expect(result.instruction == (try plan.instruction(proof: proof, treeContexts: [context])))
        #expect(result.nullifiers == selected.map(\.nullifier))
        #expect(result.lamports == spend.lamports)
        #expect(result.receivedLamports == spend.receivedLamports)
        #expect(result.nullifierCount == spend.nullifierCount)
        #expect(result.nullifierCount == plan.shape.inputs)
        #expect(result.inputTreeID == 0)
    }

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
        let response = try Self.response(for: plan.shape)
        let transport = StubTransport { request in
            guard request.url?.lastPathComponent == "prove" else { return try IndexerResponses.spendReads(answering: request) }
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

    @Test
    func `Funded transfers withdraw to the recipient's signing address`() async throws {
        let recipient = try TransferVectors.recipient()
        let notes = try [10, 5].enumerated().map { try note($1, leaf: UInt64($0)) }
        let state = try NoteSyncState(position: nil, notes: notes, outputTreeID: 0, pending: [], localSpends: [])
        let response = try Self.response(for: Shape(inputs: 2, outputs: 2))
        let transport = StubTransport { request in
            guard request.url?.lastPathComponent == "prove" else { return try IndexerResponses.spendReads(answering: request) }
            let url = try #require(request.url)
            return (response, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        }
        let solInterface = try ShieldedPool.solInterface

        let result = try await state.spend(
            6, to: .fundedTransfer(recipient, publicLamports: 5), from: sender,
            provider: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        )

        #expect(result.instruction.accounts.suffix(2).map(\.address) == [solInterface, recipient.signingAddress])
        #expect(result.nullifiers == notes.map(\.nullifier))
        #expect(result.receivedLamports == 4)
    }

    @Test
    func `Spends leave out notes whose nullifiers are already queued`() async throws {
        let recipient = try TransferVectors.recipient()
        let notes = try [10, 5].enumerated().map { try note($1, leaf: UInt64($0)) }
        let state = try NoteSyncState(position: nil, notes: notes, outputTreeID: 0, pending: [], localSpends: [])
        let queued = try ShieldedPool.nullifierAccount(tree: ShieldedPool.tree(id: 0), nullifier: notes[0].nullifier).value
        let response = try Self.response(for: Shape(inputs: 1, outputs: 2))
        let transport = StubTransport { request in
            guard request.url?.lastPathComponent == "prove" else {
                return try IndexerResponses.spendReads(answering: request, queued: [queued])
            }
            let url = try #require(request.url)
            return (response, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        }

        let result = try await state.spend(
            4, to: .transfer(recipient), from: sender, provider: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        )

        #expect(result.nullifiers == [notes[1].nullifier])
        #expect(result.receivedLamports == 1)
    }

    @Test
    func `Spends of only queued notes are insufficient`() async throws {
        let recipient = try TransferVectors.recipient()
        let notes = [try note(10, leaf: 0)]
        let state = try NoteSyncState(position: nil, notes: notes, outputTreeID: 0, pending: [], localSpends: [])
        let queued = try ShieldedPool.nullifierAccount(tree: ShieldedPool.tree(id: 0), nullifier: notes[0].nullifier).value
        let transport = StubTransport { request in try IndexerResponses.spendReads(answering: request, queued: [queued]) }
        let provider = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try await state.spend(4, to: .transfer(recipient), from: sender, provider: provider)
        }
        #expect(await transport.requests.compactMap { $0.url?.lastPathComponent } == ["/"])
    }

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

    private func note(_ lamports: UInt64, leaf: UInt64, treeID: UInt16 = 0) throws -> ReceivedNote {
        let utxo = try PlanFixtures.utxo(lamports: lamports, treeID: treeID, blindingByte: 0xa1 + UInt8(leaf))
        return ReceivedNote(
            utxo: utxo, leafIndex: leaf, signature: IndexerResponses.signature(1), slot: 1, nullifier: utxo.nullifier(using: sender.nullifierKey)
        )
    }

    private func destination(_ destination: Spend.Destination) throws -> PrivateSpend.Destination {
        switch destination {
        case .recipient: .transfer(try TransferVectors.recipient())
        case .sender: .transfer(try sender.recipient)
        case .withdrawal: .withdrawal(try Address(TransferVectors.transfers[1].payer))
        case .fundedRecipient(let publicLamports): .fundedTransfer(try TransferVectors.recipient(), publicLamports: publicLamports)
        }
    }

    private static func transfer(_ destination: PrivateSpend.Destination, lamports: UInt64) -> TransactPlan.Transfer? {
        switch destination {
        case .transfer(let recipient), .fundedTransfer(let recipient, _): TransactPlan.Transfer(recipient: recipient, lamports: lamports)
        case .withdrawal: nil
        }
    }

    private static func withdrawal(_ destination: PrivateSpend.Destination, lamports: UInt64) -> ExternalData.Withdrawal? {
        switch destination {
        case .transfer: nil
        case .withdrawal(let address): ExternalData.Withdrawal(recipient: address, lamports: lamports)
        case .fundedTransfer(let recipient, let publicLamports): ExternalData.Withdrawal(recipient: recipient.signingAddress, lamports: publicLamports)
        }
    }

    private static func response(for shape: Shape) throws -> Data {
        let vector = try #require(try ProofRequestVectors.load().transacts.first)
        var fields = try JSONDecoder().decode([String: JSONValue].self, from: vector.response.data)
        fields["provingKeySha256"] = .string(hex(shape.provingKeyDigest))
        return try JSONValue.object(fields).data
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
