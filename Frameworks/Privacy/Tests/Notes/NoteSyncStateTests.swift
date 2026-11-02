import Encoding
import Foundation
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct NoteSyncStateTests {
    private struct Indexer: Sendable {
        var transactions: [ShieldedTransaction] = []
        var deposits: [ShieldedTransaction] = []
        var spends: [ShieldedTransaction] = []
        var scanned = "AQ=="
        var outputTreeID: UInt16?

        func respond(to request: URLRequest) throws -> (Data, URLResponse) {
            switch try #require(request.url?.lastPathComponent) {
            case GetShieldedTransactionsByTags.method:
                return try reply(
                    to: request,
                    payload: IndexerResponses.page(transactions.map(IndexerResponses.row), in: "transactions", scanned: scanned, outputTreeID: outputTreeID)
                )
            case GetEncryptedUtxosByTags.method:
                return try reply(
                    to: request, payload: IndexerResponses.page(deposits.map(IndexerResponses.match), in: "matches", scanned: scanned, outputTreeID: outputTreeID)
                )
            default:
                let requested = Set(try NoteSyncStateTests.nullifiers(of: request))
                let spending = spends.filter { $0.nullifiers.contains { requested.contains(Base58.encode($0)) } }
                return try reply(to: request, payload: IndexerResponses.page(spending.map(IndexerResponses.row), in: "transactions", scanned: scanned))
            }
        }
    }

    private let sender: ShieldedAccount

    private let deposit: ShieldedTransaction

    private let laterDeposit: ShieldedTransaction

    private let largestDeposit: ShieldedTransaction

    private let foreignDeposit: ShieldedTransaction

    private let transfer: ShieldedTransaction

    init() throws {
        let vectors = try DepositNoteVectors.load().deposits
        sender = try TransferVectors.sender()
        deposit = try vectors[0].transaction(signature: IndexerResponses.signature(1), slot: 3)
        laterDeposit = try vectors[1].transaction(signature: IndexerResponses.signature(2), slot: 12)
        largestDeposit = try vectors[2].transaction(signature: IndexerResponses.signature(3), slot: 13)
        foreignDeposit = try vectors[3].transaction(signature: IndexerResponses.signature(4), slot: 4)
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        transfer = try PlanFixtures.transaction(of: plan, signature: IndexerResponses.signature(5), slot: 9)
    }

    @Test
    func `First syncs find the account's notes`() async throws {
        let (state, _) = try await sync(NoteSyncState(), with: Indexer(transactions: [transfer], deposits: [deposit, foreignDeposit]))

        #expect(state.notes == (try notes(in: deposit) + notes(in: transfer)))
        #expect(state.lamports == 1_000_006)
        #expect(state.position == NoteSyncPosition(tags: sender.viewTags, transactionCursors: ["AQ=="], outputCursors: ["AQ=="]))
    }

    @Test
    func `Resumed syncs read after the stored position`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))

        let (state, transport) = try await sync(first, with: Indexer(deposits: [laterDeposit], scanned: "Ag=="))

        let cursors = try await transport.requests.filter { $0.url?.lastPathComponent != GetShieldedTransactionsByNullifiers.method }
            .map { try #require(try requestBody($0)["params"] as? [String: Any])["cursor"] as? String }
        #expect(cursors == ["AQ==", "AQ=="])
        #expect(state.notes == (try notes(in: deposit) + notes(in: laterDeposit)))
        #expect(state.position == NoteSyncPosition(tags: sender.viewTags, transactionCursors: ["Ag=="], outputCursors: ["Ag=="]))
    }

    @Test
    func `Spends of stored notes drop them`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))

        let (state, _) = try await sync(first, with: Indexer(spends: [spend(of: first.notes)]))

        #expect(state.notes.isEmpty)
        #expect(state.lamports == 0)
    }

    @Test
    func `Spends in the batch drop stored and new notes`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: try first.notes + notes(in: laterDeposit))

        let (state, transport) = try await sync(first, with: Indexer(transactions: [spender], deposits: [laterDeposit]))

        #expect(state.notes.isEmpty)
        #expect(try await Self.nullifierReads(of: transport) == [first.notes.map { Base58.encode($0.nullifier.bigEndianBytes) }])
    }

    @Test
    func `New notes are checked for later spends`() async throws {
        let found = try notes(in: deposit)

        let (state, transport) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit], spends: [spend(of: found)]))

        #expect(state.notes.isEmpty)
        #expect(try await Self.nullifierReads(of: transport) == [found.map { Base58.encode($0.nullifier.bigEndianBytes) }])
    }

    @Test
    func `Syncs without new notes read spends once`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))

        let (state, transport) = try await sync(first, with: Indexer())

        #expect(state.notes == first.notes)
        #expect(try await Self.nullifierReads(of: transport) == [first.notes.map { Base58.encode($0.nullifier.bigEndianBytes) }])
    }

    @Test
    func `Empty states send no spending read`() async throws {
        let (state, transport) = try await sync(NoteSyncState(), with: Indexer(deposits: [foreignDeposit]))

        #expect(state.notes.isEmpty)
        #expect(try await Self.nullifierReads(of: transport).isEmpty)
    }

    @Test
    func `Repeated notes are kept once`() async throws {
        let vector = try #require(try DepositNoteVectors.load().deposits.first)
        let resent = try vector.transaction(signature: IndexerResponses.signature(6), slot: 14)

        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit, resent]))
        let (state, _) = try await sync(first, with: Indexer(deposits: [deposit]))

        #expect(first.notes == (try notes(in: deposit)))
        #expect(state == first)
    }

    @Test
    func `Totals beyond 64 bits fail the sync`() async throws {
        await #expect(throws: NoteSyncState.ValidationError.amountOverflow) {
            try await sync(NoteSyncState(), with: Indexer(deposits: [deposit, largestDeposit]))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `Tag and spend reads run at once`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let (tagsSent, tagsContinuation) = AsyncStream.makeStream(of: Void.self)
        let (spendsSent, spendsContinuation) = AsyncStream.makeStream(of: Void.self)
        let indexer = Indexer()
        let transport = StubTransport { request in
            switch request.url?.lastPathComponent {
            case GetShieldedTransactionsByTags.method:
                tagsContinuation.yield()
                var signals = spendsSent.makeAsyncIterator()
                await signals.next()
            case GetShieldedTransactionsByNullifiers.method:
                spendsContinuation.yield()
                var signals = tagsSent.makeAsyncIterator()
                await signals.next()
            default:
                break
            }
            return try indexer.respond(to: request)
        }

        let state = try await first.synced(for: sender, using: Zolana(network: .devnet, transport: transport))

        #expect(state.notes == first.notes)
    }

    @Test(.timeLimit(.minutes(1)))
    func `New notes' spend read overlaps the stored notes' spend read`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let stored = first.notes.map { Base58.encode($0.nullifier.bigEndianBytes) }
        let (newSpendsSent, continuation) = AsyncStream.makeStream(of: Void.self)
        let indexer = Indexer(deposits: [laterDeposit])
        let transport = StubTransport { request in
            if request.url?.lastPathComponent == GetShieldedTransactionsByNullifiers.method {
                if try Self.nullifiers(of: request) == stored {
                    var signals = newSpendsSent.makeAsyncIterator()
                    await signals.next()
                } else {
                    continuation.yield()
                }
            }
            return try indexer.respond(to: request)
        }

        let state = try await first.synced(for: sender, using: Zolana(network: .devnet, transport: transport))

        #expect(state.notes == (try notes(in: deposit) + notes(in: laterDeposit)))
        #expect(try await Self.nullifierReads(of: transport).count == 2)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [GetShieldedTransactionsByTags.method, GetShieldedTransactionsByNullifiers.method])
    func `A failing read fails the sync`(method: String) async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let other = method == GetShieldedTransactionsByTags.method ? GetShieldedTransactionsByNullifiers.method : GetShieldedTransactionsByTags.method
        let (otherSent, continuation) = AsyncStream.makeStream(of: Void.self)
        let transport = StubTransport { request in
            guard request.url?.lastPathComponent == method else {
                if request.url?.lastPathComponent == other { continuation.yield() }
                try await Task.sleep(for: .seconds(3_600))
                return try Indexer().respond(to: request)
            }
            var signals = otherSent.makeAsyncIterator()
            await signals.next()
            return try reply(to: request, payload: #""error":{"code":-32603,"message":"failed"}"#)
        }

        await #expect(throws: RPCError.server(code: -32603, message: "failed")) {
            try await first.synced(for: sender, using: Zolana(network: .devnet, transport: transport))
        }
        #expect(await transport.observedCancellation)
    }

    @Test
    func `Syncs read the signing and viewing key tags`() async throws {
        let record = try #require(try RegistryVectors.load().records.first { $0.owner == TransferVectors.senderSigningAddress })
        let viewingTag = Array(try fixtureBytes(record.viewingPublicKey).dropFirst())

        let (_, transport) = try await sync(NoteSyncState(), with: Indexer())

        let tags = try await transport.requests.filter { $0.url?.lastPathComponent != GetShieldedTransactionsByNullifiers.method }
            .map { try #require(try requestBody($0)["params"] as? [String: Any])["tags"] as? [String] }
        let expected = [Base58.encode(sender.signingAddress.bytes), Base58.encode(viewingTag)]
        #expect(tags == [expected, expected])
    }

    @Test
    func `Syncs keep the batch's output tree`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(outputTreeID: 3))

        let (state, _) = try await sync(first, with: Indexer())

        #expect(first.outputTreeID == 3)
        #expect(state.outputTreeID == nil)
    }

    @Test
    func `Recorded spends remove their notes at once`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit, laterDeposit]))

        let state = try first.recording(privateSpend(of: notes(in: deposit), receiving: 5), signature: IndexerResponses.signature(8))

        #expect(state.notes == (try notes(in: laterDeposit)))
        #expect(state.pendingLamports == 5)
        #expect(state.lamports == 47)
    }

    @Test
    func `Recorded spends stay hidden until the indexer reports them`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let recorded = try first.recording(privateSpend(of: first.notes, receiving: 0), signature: IndexerResponses.signature(8))

        let (unreported, _) = try await sync(recorded, with: Indexer(deposits: [deposit]))
        let (reported, _) = try await sync(unreported, with: Indexer(transactions: [spend(of: first.notes)], deposits: [deposit]))

        #expect(unreported.notes.isEmpty)
        #expect(unreported.localSpends == Set(first.notes.map(\.nullifier.bigEndianBytes)))
        #expect(reported.notes.isEmpty)
        #expect(reported.localSpends.isEmpty)
    }

    @Test
    func `Recorded spends end when the batch omits their notes`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let recorded = try first.recording(privateSpend(of: first.notes, receiving: 0), signature: IndexerResponses.signature(8))

        let (state, _) = try await sync(recorded, with: Indexer())

        #expect(state.notes.isEmpty)
        #expect(state.localSpends.isEmpty)
    }

    @Test
    func `Pending amounts end when the batch returns their transaction`() async throws {
        let recorded = try NoteSyncState().recording(depositOf: 1_000_000, signature: deposit.signature)

        let (unreported, _) = try await sync(recorded, with: Indexer())
        let (reported, _) = try await sync(unreported, with: Indexer(deposits: [deposit]))

        #expect(recorded.notes.isEmpty)
        #expect(recorded.lamports == 1_000_000)
        #expect(unreported.pendingLamports == 1_000_000)
        #expect(reported.pendingLamports == 0)
        #expect(reported.notes == (try notes(in: deposit)))
        #expect(reported.lamports == 1_000_000)
    }

    @Test
    func `Recorded deposits are counted once`() async throws {
        let (synced, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))

        let afterSync = try synced.recording(depositOf: 1_000_000, signature: deposit.signature)
        let twice = try NoteSyncState().recording(depositOf: 1_000_000, signature: deposit.signature)
            .recording(depositOf: 1_000_000, signature: deposit.signature)

        #expect(afterSync.pendingLamports == 0)
        #expect(afterSync.lamports == 1_000_000)
        #expect(twice.pendingLamports == 1_000_000)
        #expect(twice.lamports == 1_000_000)
    }

    @Test
    func `Recorded spends count their change once`() async throws {
        let (synced, _) = try await sync(NoteSyncState(), with: Indexer(transactions: [transfer], deposits: [deposit]))
        let spend = try privateSpend(of: notes(in: deposit), receiving: 6)

        let afterSync = try synced.recording(spend, signature: transfer.signature)
        let twice = try synced.recording(privateSpend(of: notes(in: deposit), receiving: 5), signature: IndexerResponses.signature(8))
            .recording(privateSpend(of: notes(in: deposit), receiving: 5), signature: IndexerResponses.signature(8))

        #expect(afterSync.pendingLamports == 0)
        #expect(afterSync.lamports == 6)
        #expect(twice.pendingLamports == 5)
        #expect(twice.lamports == 11)
    }

    @Test
    func `Spends recorded after their notes are gone add nothing pending`() async throws {
        let (synced, _) = try await sync(NoteSyncState(), with: Indexer(transactions: [transfer]))
        let (respent, _) = try await sync(synced, with: Indexer(transactions: [transfer], spends: [spend(of: synced.notes)]))
        let spent = try transfer.nullifiers.prefix(1).map { try #require(Poseidon.Element(bigEndianBytes: $0)) }
        let spend = PrivateSpend(
            instruction: Instruction(program: try ShieldedPool.program), lamports: 4, receivedLamports: 6, nullifierCount: spent.count,
            inputTreeID: 0, nullifiers: spent
        )

        let state = try respent.recording(spend, signature: transfer.signature)

        #expect(synced.lamports == 6)
        #expect(respent.notes.isEmpty)
        #expect(state.pendingLamports == 0)
        #expect(state.lamports == 0)
    }

    @Test
    func `Pending amounts end when a kept note comes from their transaction`() async throws {
        let (synced, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let pending = try NoteSyncState(
            position: synced.position, notes: synced.notes, outputTreeID: nil,
            pending: [PendingAmount(signature: deposit.signature, lamports: 1_000_000)], localSpends: []
        )

        let (state, _) = try await sync(pending, with: Indexer())

        #expect(state.pendingLamports == 0)
        #expect(state.lamports == 1_000_000)
    }

    @Test
    func `Zero-lamport deposits can't be recorded`() {
        #expect(throws: ValidationError.invalidAmount) {
            try NoteSyncState().recording(depositOf: 0, signature: IndexerResponses.signature(8))
        }
    }

    @Test
    func `Records beyond 64 bits are rejected`() async throws {
        let (largest, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [largestDeposit]))

        #expect(throws: NoteSyncState.ValidationError.amountOverflow) {
            try largest.recording(depositOf: 1_000_000, signature: IndexerResponses.signature(8))
        }
    }

    @Test
    func `States survive encoding`() async throws {
        let (state, _) = try await sync(NoteSyncState(), with: Indexer(transactions: [transfer], deposits: [deposit]))

        let decoded = try JSONDecoder().decode(NoteSyncState.self, from: JSONEncoder().encode(state))

        #expect(decoded == state)
    }

    @Test
    func `Recorded states survive encoding`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit, laterDeposit], outputTreeID: 2))
        let state = try first.recording(privateSpend(of: notes(in: deposit), receiving: 5), signature: IndexerResponses.signature(8))

        let decoded = try JSONDecoder().decode(NoteSyncState.self, from: JSONEncoder().encode(state))

        #expect(decoded == state)
        #expect(decoded.outputTreeID == 2)
        #expect(decoded.pendingLamports == 5)
        #expect(!decoded.localSpends.isEmpty)
    }

    @Test(arguments: ["notes", "outputTreeID", "pending", "localSpends"])
    func `Encoded states without a field are rejected`(key: String) async throws {
        var fields = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteSyncState())) as? [String: Any])
        fields[key] = nil
        let encoded = try JSONSerialization.data(withJSONObject: fields)

        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(NoteSyncState.self, from: encoded)
        }

        guard case .keyNotFound(let missing, _) = error else {
            Issue.record("Expected a missing key, not \(String(describing: error)).")
            return
        }
        #expect(missing.stringValue == key)
    }

    @Test
    func `Encoded nullifiers of another length are rejected`() throws {
        var fields = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteSyncState())) as? [String: Any])
        fields["localSpends"] = [Data(repeating: 1, count: 31).base64EncodedString()]
        let encoded = try JSONSerialization.data(withJSONObject: fields)

        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(NoteSyncState.self, from: encoded)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected corrupted data, not \(String(describing: error)).")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["localSpends"])
    }

    @Test
    func `Encoded totals beyond 64 bits are rejected`() async throws {
        let (largest, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [largestDeposit]))
        let (small, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        var fields = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(largest)) as? [String: Any])
        let notes = try #require(fields["notes"] as? [Any])
        let other = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(small)) as? [String: Any])
        fields["notes"] = notes + (try #require(other["notes"] as? [Any]))
        let encoded = try JSONSerialization.data(withJSONObject: fields)

        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(NoteSyncState.self, from: encoded)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected corrupted data, not \(String(describing: error)).")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["notes"])
    }

    @Test
    func `State diagnostics omit the values`() async throws {
        let (state, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        var dumped = ""
        dump(state, to: &dumped)

        #expect(String(describing: state) == "NoteSyncState")
        #expect(String(reflecting: state) == "NoteSyncState")
        #expect(dumped == "- NoteSyncState\n")
    }

    private func sync(_ state: NoteSyncState, with indexer: Indexer) async throws -> (NoteSyncState, StubTransport) {
        let transport = StubTransport { try indexer.respond(to: $0) }
        let synced = try await state.synced(for: sender, using: Zolana(network: .devnet, transport: transport))
        return (synced, transport)
    }

    private func notes(in transaction: ShieldedTransaction) throws -> [ReceivedNote] {
        try ReceivedNote.notes(in: transaction, of: sender)
    }

    private func spend(of notes: [ReceivedNote]) -> ShieldedTransaction {
        ShieldedTransaction(
            signature: IndexerResponses.signature(7), slot: 20, eventIndex: 0, transactionViewingKey: nil, salt: nil, outputs: [],
            nullifiers: notes.map(\.nullifier.bigEndianBytes), isProofless: false
        )
    }

    private func privateSpend(of notes: [ReceivedNote], receiving lamports: UInt64) throws -> PrivateSpend {
        PrivateSpend(
            instruction: Instruction(program: try ShieldedPool.program), lamports: 1, receivedLamports: lamports,
            nullifierCount: notes.count, inputTreeID: 0, nullifiers: notes.map(\.nullifier)
        )
    }

    private static func nullifiers(of request: URLRequest) throws -> [String] {
        let params = try #require(try requestBody(request)["params"] as? [String: Any])
        return try #require(params["nullifiers"] as? [String])
    }

    private static func nullifierReads(of transport: StubTransport) async throws -> [[String]] {
        try await transport.requests.filter { $0.url?.lastPathComponent == GetShieldedTransactionsByNullifiers.method }.map(nullifiers)
    }
}
