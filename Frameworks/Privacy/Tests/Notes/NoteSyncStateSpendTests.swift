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
        let amount: UInt64
        let asset: PrivateAsset
        let destination: Destination
        let selected: [Int]
        let transferAmount: UInt64?
        let withdrawalAmount: UInt64?
        let receivedAmount: UInt64
    }

    static let spends = [
        Spend(
            testDescription: "transfer with change", notes: [3, 10, 5], amount: 12, asset: .nativeSOL, destination: .recipient,
            selected: [1, 2], transferAmount: 12, withdrawalAmount: nil, receivedAmount: 3
        ),
        Spend(
            testDescription: "exact withdrawal", notes: [3, 10], amount: 10, asset: .nativeSOL, destination: .withdrawal, selected: [1],
            transferAmount: nil, withdrawalAmount: 10, receivedAmount: 0
        ),
        Spend(
            testDescription: "transfer to the sender", notes: [10], amount: 4, asset: .nativeSOL, destination: .sender, selected: [0],
            transferAmount: 4, withdrawalAmount: nil, receivedAmount: 10
        ),
        Spend(
            testDescription: "funded transfer", notes: [3, 10, 5], amount: 6, asset: .nativeSOL,
            destination: .fundedRecipient(publicLamports: 5), selected: [1, 2], transferAmount: 6, withdrawalAmount: 5, receivedAmount: 4
        ),
        Spend(
            testDescription: "token withdrawal with change", notes: [10], amount: 4, asset: .token(.usdc), destination: .withdrawal,
            selected: [0], transferAmount: nil, withdrawalAmount: 4, receivedAmount: 6
        ),
        Spend(
            testDescription: "withdrawal with a padding input", notes: [1, 1, 1, 1, 1, 1, 1], amount: 7, asset: .nativeSOL,
            destination: .withdrawal, selected: [0, 1, 2, 3, 4, 5, 6], transferAmount: nil, withdrawalAmount: 7, receivedAmount: 0
        ),
    ]

    private let sender: ShieldedAccount

    init() throws {
        sender = try TransferVectors.sender()
    }

    @Test(arguments: spends)
    func `Spends prove a plan of the selected notes`(_ spend: Spend) async throws {
        let notes = try spend.notes.enumerated().map { try note($1, leaf: UInt64($0), asset: spend.asset) }
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )
        let destination = try destination(spend.destination)
        let selected = spend.selected.map { notes[$0] }
        var planGenerator = SeededGenerator(seed: 7)
        let plan = try TransactPlan(
            spending: selected.map(\.utxo), of: spend.asset, sender: sender,
            transfer: try spend.transferAmount.map { TransactPlan.Transfer(recipient: try shieldedRecipient(of: spend.destination), amount: $0) },
            withdrawal: try spend.withdrawalAmount.map {
                ExternalData.Withdrawal(
                    recipient: try withdrawalAccount(of: spend.destination, holding: spend.asset), amount: $0, asset: spend.asset
                )
            },
            outputTreeID: 0, using: &planGenerator
        )
        let proof = try plan.proof(from: IndexedProofs.proof(for: plan.shape))
        let context = TreeContext(
            utxoTreeRootIndex: IndexedProofs.utxoRootIndex, nullifierTreeRootIndex: IndexedProofs.nullifierRootIndex
        )
        let transport = try Self.transport()
        var spendGenerator = SeededGenerator(seed: 7)

        let result = try await state.spend(
            spend.amount, of: spend.asset, to: destination, from: sender, rpc: SolanaRPC.devnet(transport: transport),
            prover: Self.prover(transport), using: &spendGenerator
        )

        let routes = await transport.requests.compactMap { $0.url?.path() }
        let route = "/prove/transfer_confidential_\(plan.shape.inputs)_\(plan.shape.outputs)/indexed"
        #expect(routes == ["", "/attestation", route])
        let transact = try plan.instruction(proof: proof, treeContexts: [context])
        let openings = try openings(of: spend)
        #expect(result.instructions == openings.map(\.instruction) + [transact])
        #expect(result.openedAccounts == openings.map(\.account))
        #expect(result.nullifiers == selected.map(\.nullifier))
        #expect(result.amount == spend.amount)
        #expect(result.receivedAmount == spend.receivedAmount)
        #expect(result.treeIDs == [0])
    }

    @Test
    func `Spends name the tree of their selected notes and their output tree`() async throws {
        let notes = [try note(3, leaf: 0, asset: .nativeSOL), try note(4, leaf: 1, asset: .nativeSOL), try note(10, leaf: 2, treeID: 2, asset: .nativeSOL)]

        let result = try await spend(9, of: notes)

        #expect(result.treeIDs == [2, 0])
        #expect(result.nullifiers == [notes[2].nullifier])
    }

    @Test
    func `Spends leave out notes whose nullifiers are already queued`() async throws {
        let recipient = try TransferVectors.recipient()
        let notes = try [10, 5].enumerated().map { try note($1, leaf: UInt64($0), asset: .nativeSOL) }
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )
        let queued = try ShieldedPool.nullifierAccount(tree: ShieldedPool.tree(id: 0), nullifier: notes[0].nullifier).value
        let transport = try Self.transport(queued: [queued])

        let result = try await state.spend(
            4, of: .nativeSOL, to: .transfer(recipient), from: sender, rpc: SolanaRPC.devnet(transport: transport), prover: Self.prover(transport)
        )

        #expect(result.nullifiers == [notes[1].nullifier])
        #expect(result.receivedAmount == 1)
    }

    @Test
    func `Spends leave out notes that an unsettled spend claim names`() async throws {
        let recipient = try TransferVectors.recipient()
        let notes = try [10, 5].enumerated().map { try note($1, leaf: UInt64($0), asset: .nativeSOL) }
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            claimedSpends: [notes[0].nullifier.bigEndianBytes], rejectedSpends: [], missingSpendReads: [:]
        )
        let transport = try Self.transport()

        let result = try await state.spend(
            4, of: .nativeSOL, to: .transfer(recipient), from: sender, rpc: SolanaRPC.devnet(transport: transport), prover: Self.prover(transport)
        )

        #expect(state.spendableAmount(of: .nativeSOL) == 5)
        #expect(result.nullifiers == [notes[1].nullifier])
        #expect(result.receivedAmount == 1)
    }

    @Test
    func `Spends of only queued notes are insufficient`() async throws {
        let recipient = try TransferVectors.recipient()
        let notes = [try note(10, leaf: 0, asset: .nativeSOL)]
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )
        let queued = try ShieldedPool.nullifierAccount(tree: ShieldedPool.tree(id: 0), nullifier: notes[0].nullifier).value
        let transport = StubTransport { request in try IndexerResponses.spendReads(answering: request, queued: [queued]) }

        await #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try await state.spend(4, of: .nativeSOL, to: .transfer(recipient), from: sender,
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
        let state = try NoteSyncState(position: nil, notes: [try note(10, leaf: 0, asset: .nativeSOL)], unconfirmedNotes: [], outputTreeID: 0, pending: [],
                                      localSpends: [], claimedSpends: [], rejectedSpends: [], missingSpendReads: [:])
        let destination = try self.destination(destination)

        await #expect(throws: ValidationError.invalidAmount) {
            try await state.spend(lamports, of: .nativeSOL, to: destination, from: sender, rpc: SolanaRPC.devnet(transport: transport),
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
            position: nil, notes: notes.enumerated().map { try note($1, leaf: UInt64($0), asset: .nativeSOL) }, unconfirmedNotes: [],
            outputTreeID: outputTreeID,
            pending: pendingLamports.map { PendingAmount(signature: IndexerResponses.signature(1), asset: .nativeSOL, amount: $0) }, localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )
        let destination = try self.destination(destination)

        await #expect(throws: error) {
            try await state.spend(lamports, of: .nativeSOL, to: destination, from: sender, rpc: SolanaRPC.devnet(transport: transport),
                                  prover: Self.prover(transport))
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `Unconfirmed notes can't be spent`() async throws {
        let transport = StubTransport { _ in throw CancellationError() }
        let state = try NoteSyncState(position: nil, notes: [], unconfirmedNotes: [try note(10, leaf: 0, asset: .nativeSOL)], outputTreeID: 0, pending: [],
                                      localSpends: [], claimedSpends: [], rejectedSpends: [], missingSpendReads: [:])

        await #expect(throws: PrivateSpend.ValidationError.insufficientFunds) {
            try await state.spend(4, of: .nativeSOL, to: .transfer(try TransferVectors.recipient()), from: sender, rpc: SolanaRPC.devnet(transport: transport),
                                  prover: Self.prover(transport))
        }
        #expect(state.spendableAmount(of: .nativeSOL) == 0)
        #expect(await transport.requests.isEmpty)
    }

    private func spend(_ lamports: UInt64, of notes: [ReceivedNote]) async throws -> PrivateSpend {
        let state = try NoteSyncState(
            position: nil, notes: notes, unconfirmedNotes: [], outputTreeID: 0, pending: [], localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )
        let transport = try Self.transport()
        var generator = SeededGenerator(seed: 7)
        return try await state.spend(
            lamports, of: .nativeSOL, to: .transfer(try TransferVectors.recipient()), from: sender, rpc: SolanaRPC.devnet(transport: transport),
            prover: Self.prover(transport), using: &generator
        )
    }

    private func note(
        _ amount: UInt64, leaf: UInt64, treeID: UInt16 = 0, asset: PrivateAsset
    ) throws -> ReceivedNote {
        let utxo = try PlanFixtures.utxo(amount: amount, treeID: treeID, blindingByte: 0xa1 + UInt8(leaf), asset: asset)
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

    private func shieldedRecipient(of destination: Spend.Destination) throws -> Recipient {
        if case .sender = destination { try sender.recipient } else { try TransferVectors.recipient() }
    }

    private func withdrawalAccount(of destination: Spend.Destination, holding asset: PrivateAsset) throws -> Address {
        if case .fundedRecipient = destination { return try TransferVectors.recipient().signingAddress }
        let owner = try Address(TransferVectors.transfers[1].payer)
        return switch asset {
        case .nativeSOL: owner
        case .token(let token): try TokenProgram.token.associatedAccount(owner: owner, mint: token.mint)
        }
    }

    private func openings(of spend: Spend) throws -> [(account: Address, instruction: Instruction)] {
        guard case .withdrawal = spend.destination, case .token(let token) = spend.asset else { return [] }
        let owner = try Address(TransferVectors.transfers[1].payer)
        return [(
            try withdrawalAccount(of: spend.destination, holding: spend.asset),
            try AssociatedTokenProgram.createIdempotent(owner: owner, mint: token.mint, program: .token,
                                                        payer: sender.signingAddress)
        )]
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
