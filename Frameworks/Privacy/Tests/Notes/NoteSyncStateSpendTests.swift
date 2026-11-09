import Foundation
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy
@testable import RPC

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
    }

    static let spends = [
        Spend(
            testDescription: "transfer with change", notes: [3, 10, 5], lamports: 12, destination: .recipient, selected: [1, 2],
            receivedLamports: 3
        ),
        Spend(
            testDescription: "exact withdrawal", notes: [3, 10], lamports: 10, destination: .withdrawal, selected: [1], receivedLamports: 0
        ),
        Spend(
            testDescription: "transfer to the sender", notes: [10], lamports: 4, destination: .sender, selected: [0], receivedLamports: 10
        ),
        Spend(
            testDescription: "funded transfer", notes: [3, 10, 5], lamports: 6, destination: .fundedRecipient(publicLamports: 5),
            selected: [1, 2], receivedLamports: 4
        ),
        Spend(
            testDescription: "withdrawal with a padding input", notes: [1, 1, 1, 1, 1, 1, 1], lamports: 7, destination: .withdrawal,
            selected: [0, 1, 2, 3, 4, 5, 6], receivedLamports: 0
        ),
    ]

    private let sender: ShieldedAccount

    init() throws {
        sender = try TransferVectors.sender()
    }

    @Test(arguments: spends)
    func `Spends prove a plan of the selected notes`(_ spend: Spend) async throws {
        let notes = try spend.notes.enumerated().map { try note($1, leaf: UInt64($0)) }
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            rejectedSpends: [], missingSpendReads: [:]
        )
        let destination = try destination(spend.destination)
        let selected = spend.selected.map { notes[$0] }
        var planGenerator = SeededGenerator(seed: 7)
        let plan = try TransactPlan(
            spending: selected.map(\.utxo), sender: sender, transfer: Self.transfer(destination, lamports: spend.lamports),
            withdrawal: Self.withdrawal(destination, lamports: spend.lamports), outputTreeID: 0, using: &planGenerator
        )
        let proof = try plan.proof(from: IndexedProofs.proof(for: plan.shape))
        let context = TreeContext(
            utxoTreeRootIndex: IndexedProofs.utxoRootIndex, nullifierTreeRootIndex: IndexedProofs.nullifierRootIndex
        )
        let transport = try Self.transport()
        var spendGenerator = SeededGenerator(seed: 7)

        let result = try await state.spend(
            spend.lamports, to: destination, from: sender, rpc: SolanaRPC.devnet(transport: transport), prover: Self.prover(transport),
            using: &spendGenerator
        )

        let routes = await transport.requests.compactMap { $0.url?.path() }
        let route = "/prove/transfer_confidential_\(plan.shape.inputs)_\(plan.shape.outputs)/indexed"
        #expect(routes == ["", "/attestation", route])
        #expect(result.instruction == (try plan.instruction(proof: proof, treeContexts: [context])))
        #expect(result.nullifiers == selected.map(\.nullifier))
        #expect(result.lamports == spend.lamports)
        #expect(result.receivedLamports == spend.receivedLamports)
        #expect(result.treeIDs == [0])
    }

    @Test
    func `Spends name the tree of their selected notes and their output tree`() async throws {
        let notes = [try note(3, leaf: 0), try note(4, leaf: 1), try note(10, leaf: 2, treeID: 2)]

        let result = try await spend(9, of: notes)

        #expect(result.treeIDs == [2, 0])
        #expect(result.nullifiers == [notes[2].nullifier])
    }

    @Test
    func `Spends take the output tree's notes over another tree's fewer notes`() async throws {
        let notes = [
            try note(4, leaf: 0), try note(4, leaf: 1), try note(4, leaf: 2), try note(9, leaf: 3, treeID: 1),
            try note(2, leaf: 4, treeID: 1),
        ]

        let result = try await spend(10, of: notes)

        #expect(result.treeIDs == [0])
        #expect(result.nullifiers == notes.prefix(3).map(\.nullifier))
    }

    @Test
    func `Spends draw from two trees when no one tree covers them`() async throws {
        let notes = [try note(6, leaf: 0, treeID: 1), try note(6, leaf: 1, treeID: 2)]

        let result = try await spend(10, of: notes)

        #expect(result.treeIDs == [0, 1, 2])
        #expect(result.nullifiers == notes.map(\.nullifier))
        #expect(result.receivedLamports == 2)
    }

    @Test
    func `Funded transfers withdraw to the recipient's signing address`() async throws {
        let recipient = try TransferVectors.recipient()
        let notes = try [10, 5].enumerated().map { try note($1, leaf: UInt64($0)) }
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            rejectedSpends: [], missingSpendReads: [:]
        )
        let transport = try Self.transport()
        let solInterface = try ShieldedPool.solInterface

        let result = try await state.spend(
            6, to: .fundedTransfer(recipient, publicLamports: 5), from: sender, rpc: SolanaRPC.devnet(transport: transport),
            prover: Self.prover(transport)
        )

        #expect(result.instruction.accounts.suffix(2).map(\.address) == [solInterface, recipient.signingAddress])
        #expect(result.nullifiers == notes.map(\.nullifier))
        #expect(result.receivedLamports == 4)
    }

    @Test
    func `Spends leave out notes whose nullifiers are already queued`() async throws {
        let recipient = try TransferVectors.recipient()
        let notes = try [10, 5].enumerated().map { try note($1, leaf: UInt64($0)) }
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            rejectedSpends: [], missingSpendReads: [:]
        )
        let queued = try ShieldedPool.nullifierAccount(tree: ShieldedPool.tree(id: 0), nullifier: notes[0].nullifier).value
        let transport = try Self.transport(queued: [queued])

        let result = try await state.spend(
            4, to: .transfer(recipient), from: sender, rpc: SolanaRPC.devnet(transport: transport), prover: Self.prover(transport)
        )

        #expect(result.nullifiers == [notes[1].nullifier])
        #expect(result.receivedLamports == 1)
    }

    @Test
    func `Spends of only queued notes are insufficient`() async throws {
        let recipient = try TransferVectors.recipient()
        let notes = [try note(10, leaf: 0)]
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            rejectedSpends: [], missingSpendReads: [:]
        )
        let queued = try ShieldedPool.nullifierAccount(tree: ShieldedPool.tree(id: 0), nullifier: notes[0].nullifier).value
        let transport = StubTransport { request in try IndexerResponses.spendReads(answering: request, queued: [queued]) }

        await #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try await state.spend(4, to: .transfer(recipient), from: sender,
                                  rpc: SolanaRPC.devnet(transport: transport), prover: Self.prover(transport))
        }
        #expect(await transport.requests.compactMap { $0.url?.host() } == ["api.devnet.solana.com"])
    }

    @Test(arguments: [
        (UInt64(0), Spend.Destination.recipient),
        (4, .fundedRecipient(publicLamports: 0)),
        (4, .fundedRecipient(publicLamports: .max)),
    ])
    func `Invalid amounts send no request`(lamports: UInt64, destination: Spend.Destination) async throws {
        let transport = StubTransport { _ in throw CancellationError() }
        let state = try NoteSyncState(position: nil, notes: [try note(10, leaf: 0)], unconfirmedNotes: [], outputTreeID: 0, pending: [],
                                      localSpends: [], rejectedSpends: [], missingSpendReads: [:])
        let destination = try self.destination(destination)

        await #expect(throws: ValidationError.invalidAmount) {
            try await state.spend(lamports, to: destination, from: sender, rpc: SolanaRPC.devnet(transport: transport),
                                  prover: Self.prover(transport))
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
        let state = try NoteSyncState(
            position: nil, notes: notes.enumerated().map { try note($1, leaf: UInt64($0)) }, unconfirmedNotes: [],
            outputTreeID: outputTreeID,
            pending: pendingLamports.map { PendingAmount(signature: IndexerResponses.signature(1), lamports: $0) }, localSpends: [],
            rejectedSpends: [], missingSpendReads: [:]
        )
        let destination = try self.destination(destination)

        await #expect(throws: error) {
            try await state.spend(lamports, to: destination, from: sender, rpc: SolanaRPC.devnet(transport: transport),
                                  prover: Self.prover(transport))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `Unconfirmed notes can't be spent`() async throws {
        let transport = StubTransport { _ in throw CancellationError() }
        let state = try NoteSyncState(position: nil, notes: [], unconfirmedNotes: [try note(10, leaf: 0)], outputTreeID: 0, pending: [],
                                      localSpends: [], rejectedSpends: [], missingSpendReads: [:])

        await #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try await state.spend(4, to: .transfer(try TransferVectors.recipient()), from: sender, rpc: SolanaRPC.devnet(transport: transport),
                                  prover: Self.prover(transport))
        }
        #expect(state.spendableLamports == 0)
        #expect(await transport.requests.isEmpty)
    }

    private func spend(_ lamports: UInt64, of notes: [ReceivedNote]) async throws -> PrivateSpend {
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            rejectedSpends: [], missingSpendReads: [:]
        )
        let transport = try Self.transport()
        var generator = SeededGenerator(seed: 7)
        return try await state.spend(
            lamports, to: .transfer(try TransferVectors.recipient()), from: sender, rpc: SolanaRPC.devnet(transport: transport),
            prover: Self.prover(transport), using: &generator
        )
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

    private static func transport(queued: Set<String> = []) throws -> StubTransport {
        let prover = try IndexedProofs.prover()
        return StubTransport { request in
            try prover.respond(to: request) ?? IndexerResponses.spendReads(answering: request, queued: queued)
        }
    }

    private static func prover(_ transport: StubTransport) -> Zolana {
        StubProver.zolana(transport: transport)
    }
}
