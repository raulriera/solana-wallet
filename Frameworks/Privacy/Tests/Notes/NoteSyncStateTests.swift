import Encoding
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

/// Verifies note syncs through the real Helius client with local indexer responses: the notes that
/// they find and drop, the reads that they send, the transactions that they record, and the states'
/// encoding.
///
/// The sender's notes come from deposit vectors and from the change of a transact plan.
struct NoteSyncStateTests {
    /// The indexer's contents for one sync.
    private struct Indexer: Sendable {
        /// The confidential transactions that the tag reads return.
        var transactions: [ShieldedTransaction] = []
        /// The proofless deposits that the tag reads return.
        var deposits: [ShieldedTransaction] = []
        /// The transactions that the nullifier reads return when they spend a requested nullifier.
        var spends: [ShieldedTransaction] = []
        /// The position that every page reports.
        var scanned = "AQ=="
        /// The output tree that every tag page reports, if any.
        var outputTreeID: UInt16?

        /// Answers an indexer request from the contents.
        ///
        /// - Parameter request: A tag or nullifier read.
        /// - Returns: The read's only page.
        /// - Throws: A test prerequisite error if the request isn't an indexer read.
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

    /// The account whose notes sync.
    private let sender: ShieldedAccount

    /// A deposit of 1,000,000 lamports to the sender, at slot 3.
    private let deposit: ShieldedTransaction

    /// A deposit of 42 lamports to the sender, at slot 12.
    private let laterDeposit: ShieldedTransaction

    /// A deposit of the largest amount to the sender, at slot 13.
    private let largestDeposit: ShieldedTransaction

    /// A deposit to another owner, at slot 4.
    private let foreignDeposit: ShieldedTransaction

    /// A transfer of 4 of the sender's 10 lamports, which leaves 6 lamports of change, at slot 9.
    private let transfer: ShieldedTransaction

    /// Loads the deposits and plans the transfer.
    ///
    /// - Throws: A test failure if a fixture is missing or malformed, or an error if the plan can't be built.
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

    /// Verifies that a first sync finds the sender's deposit and change, not another owner's deposit,
    /// in slot order, and stores both streams' positions.
    @Test
    func `First syncs find the account's notes`() async throws {
        let (state, _) = try await sync(NoteSyncState(), with: Indexer(transactions: [transfer], deposits: [deposit, foreignDeposit]))

        #expect(state.notes == (try notes(in: deposit) + notes(in: transfer)))
        #expect(state.lamports == 1_000_006)
        #expect(state.position == NoteSyncPosition(tags: sender.viewTags, transactionCursors: ["AQ=="], outputCursors: ["AQ=="]))
    }

    /// Verifies that a later sync reads both streams after the stored position and keeps the earlier
    /// notes.
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

    /// Verifies that a stored note drops once the nullifier read returns its spend.
    @Test
    func `Spends of stored notes drop them`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))

        let (state, _) = try await sync(first, with: Indexer(spends: [spend(of: first.notes)]))

        #expect(state.notes.isEmpty)
        #expect(state.lamports == 0)
    }

    /// Verifies that a transaction of the batch that publishes the nullifiers of a stored note and a
    /// new note drops both, so the new note needs no further read.
    @Test
    func `Spends in the batch drop stored and new notes`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: try first.notes + notes(in: laterDeposit))

        let (state, transport) = try await sync(first, with: Indexer(transactions: [spender], deposits: [laterDeposit]))

        #expect(state.notes.isEmpty)
        #expect(try await Self.nullifierReads(of: transport) == [first.notes.map { Base58.encode($0.nullifier.bigEndianBytes) }])
    }

    /// Verifies that new unspent notes get one more nullifier read, which finds their later spend.
    @Test
    func `New notes are checked for later spends`() async throws {
        let found = try notes(in: deposit)

        let (state, transport) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit], spends: [spend(of: found)]))

        #expect(state.notes.isEmpty)
        #expect(try await Self.nullifierReads(of: transport) == [found.map { Base58.encode($0.nullifier.bigEndianBytes) }])
    }

    /// Verifies that a sync without new notes reads the stored notes' spends once.
    @Test
    func `Syncs without new notes read spends once`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))

        let (state, transport) = try await sync(first, with: Indexer())

        #expect(state.notes == first.notes)
        #expect(try await Self.nullifierReads(of: transport) == [first.notes.map { Base58.encode($0.nullifier.bigEndianBytes) }])
    }

    /// Verifies that a sync without stored or new notes sends no nullifier read.
    @Test
    func `Empty states send no spending read`() async throws {
        let (state, transport) = try await sync(NoteSyncState(), with: Indexer(deposits: [foreignDeposit]))

        #expect(state.notes.isEmpty)
        #expect(try await Self.nullifierReads(of: transport).isEmpty)
    }

    /// Verifies that a note that the indexer returns again, in a later batch or under another
    /// signature, is kept once.
    @Test
    func `Repeated notes are kept once`() async throws {
        let vector = try #require(try DepositNoteVectors.load().deposits.first)
        let resent = try vector.transaction(signature: IndexerResponses.signature(6), slot: 14)

        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit, resent]))
        let (state, _) = try await sync(first, with: Indexer(deposits: [deposit]))

        #expect(first.notes == (try notes(in: deposit)))
        #expect(state == first)
    }

    /// Verifies that notes whose total exceeds a 64-bit integer fail the sync.
    @Test
    func `Totals beyond 64 bits fail the sync`() async throws {
        await #expect(throws: NoteSyncState.ValidationError.amountOverflow) {
            try await sync(NoteSyncState(), with: Indexer(deposits: [deposit, largestDeposit]))
        }
    }

    /// Verifies that the tag read and the stored notes' nullifier read run at once: each answers only
    /// after the other reaches the transport, so reading them one after the other in either order
    /// exceeds the time limit.
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

        let state = try await first.synced(for: sender, using: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport))

        #expect(state.notes == first.notes)
    }

    /// Verifies that the new notes' nullifier read starts while the stored notes' nullifier read
    /// still runs: the stored notes' read answers only after the new notes' read reaches the
    /// transport.
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

        let state = try await first.synced(for: sender, using: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport))

        #expect(state.notes == (try notes(in: deposit) + notes(in: laterDeposit)))
        #expect(try await Self.nullifierReads(of: transport).count == 2)
    }

    /// Verifies that a failing tag or nullifier read fails the sync and cancels the other read: the
    /// failing read answers with an RPC error only after the other read reaches the transport.
    ///
    /// - Parameter method: The read that fails.
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
            try await first.synced(for: sender, using: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport))
        }
        #expect(await transport.observedCancellation)
    }

    /// Verifies that both tag reads request the signing address and the viewing public key's
    /// x-coordinate, from the sender's independent registry record.
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

    /// Verifies that a sync keeps the output tree of its batch, and none when the indexer reports
    /// none.
    @Test
    func `Syncs keep the batch's output tree`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(outputTreeID: 3))

        let (state, _) = try await sync(first, with: Indexer())

        #expect(first.outputTreeID == 3)
        #expect(state.outputTreeID == nil)
    }

    /// Verifies that a recorded spend removes its notes at once and keeps its change pending.
    @Test
    func `Recorded spends remove their notes at once`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit, laterDeposit]))

        let state = try first.recording(privateSpend(of: notes(in: deposit), receiving: 5), signature: IndexerResponses.signature(8))

        #expect(state.notes == (try notes(in: laterDeposit)))
        #expect(state.pendingLamports == 5)
        #expect(state.lamports == 47)
    }

    /// Verifies that a recorded spend's note stays hidden while the indexer returns it again
    /// without its spend, and stops being tracked once the indexer reports the spend.
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

    /// Verifies that a recorded spend stops being tracked when the batch doesn't return its note.
    @Test
    func `Recorded spends end when the batch omits their notes`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let recorded = try first.recording(privateSpend(of: first.notes, receiving: 0), signature: IndexerResponses.signature(8))

        let (state, _) = try await sync(recorded, with: Indexer())

        #expect(state.notes.isEmpty)
        #expect(state.localSpends.isEmpty)
    }

    /// Verifies that a recorded deposit stays pending, counted but not a note, until the batch
    /// returns its transaction, whose note then counts instead.
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

    /// Verifies that a deposit that a sync already returned, or that's recorded twice, is counted
    /// once.
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

    /// Verifies that a spend whose change a sync already returned, or that's recorded twice, counts
    /// its change once.
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

    /// Verifies that a spend recorded after a sync saw its transaction and its change was spent
    /// elsewhere adds nothing pending, since none of its spent notes is still held.
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

    /// Verifies that a pending amount ends once a kept note comes from its transaction, even when the
    /// batch doesn't return the transaction again.
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

    /// Verifies that a zero-lamport deposit can't be recorded.
    @Test
    func `Zero-lamport deposits can't be recorded`() {
        #expect(throws: ValidationError.invalidAmount) {
            try NoteSyncState().recording(depositOf: 0, signature: IndexerResponses.signature(8))
        }
    }

    /// Verifies that a record whose total would exceed a 64-bit integer is rejected.
    @Test
    func `Records beyond 64 bits are rejected`() async throws {
        let (largest, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [largestDeposit]))

        #expect(throws: NoteSyncState.ValidationError.amountOverflow) {
            try largest.recording(depositOf: 1_000_000, signature: IndexerResponses.signature(8))
        }
    }

    /// Verifies that a state with notes and a position decodes to itself.
    @Test
    func `States survive encoding`() async throws {
        let (state, _) = try await sync(NoteSyncState(), with: Indexer(transactions: [transfer], deposits: [deposit]))

        let decoded = try JSONDecoder().decode(NoteSyncState.self, from: JSONEncoder().encode(state))

        #expect(decoded == state)
    }

    /// Verifies that a state with an output tree, a pending amount, and a recorded spend decodes to
    /// itself.
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

    /// Verifies that an encoded state without one of its fields is rejected.
    ///
    /// - Parameter key: The removed field.
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

    /// Verifies that an encoded recorded spend whose nullifier isn't 32 bytes is rejected.
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

    /// Verifies that an encoded state whose notes' total exceeds a 64-bit integer is rejected as
    /// corrupted notes.
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

    /// Verifies that printing, dumping, and reflecting a state omit its values.
    @Test
    func `State diagnostics omit the values`() async throws {
        let (state, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        var dumped = ""
        dump(state, to: &dumped)

        #expect(String(describing: state) == "NoteSyncState")
        #expect(String(reflecting: state) == "NoteSyncState")
        #expect(dumped == "- NoteSyncState\n")
    }

    /// Syncs the sender's state through the real Helius client and an indexer's contents.
    ///
    /// - Parameters:
    ///   - state: The state to sync.
    ///   - indexer: The indexer's contents.
    /// - Returns: The synced state and the transport that recorded the reads.
    /// - Throws: An error from the sync.
    private func sync(_ state: NoteSyncState, with indexer: Indexer) async throws -> (NoteSyncState, StubTransport) {
        let transport = StubTransport { try indexer.respond(to: $0) }
        let synced = try await state.synced(for: sender, using: HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport))
        return (synced, transport)
    }

    /// Finds the sender's notes in a transaction.
    ///
    /// - Parameter transaction: The transaction.
    /// - Returns: The notes.
    /// - Throws: An error from opening a note.
    private func notes(in transaction: ShieldedTransaction) throws -> [ReceivedNote] {
        try ReceivedNote.notes(in: transaction, of: sender)
    }

    /// Creates a transaction without outputs that spends notes.
    ///
    /// - Parameter notes: The spent notes.
    /// - Returns: The transaction, at slot 20.
    private func spend(of notes: [ReceivedNote]) -> ShieldedTransaction {
        ShieldedTransaction(
            signature: IndexerResponses.signature(7), slot: 20, eventIndex: 0, transactionViewingKey: nil, salt: nil, outputs: [],
            nullifiers: notes.map(\.nullifier.bigEndianBytes), isProofless: false
        )
    }

    /// Creates a spend of notes whose transaction succeeded, without its proof.
    ///
    /// - Parameters:
    ///   - notes: The spent notes.
    ///   - lamports: The lamports of the outputs that the sender owns.
    /// - Returns: The spend.
    /// - Throws: An error if the program's address doesn't decode, which doesn't happen.
    private func privateSpend(of notes: [ReceivedNote], receiving lamports: UInt64) throws -> PrivateSpend {
        PrivateSpend(
            instruction: Instruction(program: try ShieldedPool.program), lamports: 1, receivedLamports: lamports,
            nullifierCount: notes.count, inputTreeID: 0, nullifiers: notes.map(\.nullifier)
        )
    }

    /// Reads the base-58 nullifiers that a nullifier read requests.
    ///
    /// - Parameter request: The read.
    /// - Returns: The nullifiers.
    /// - Throws: A test prerequisite error if the request has no nullifiers.
    private static func nullifiers(of request: URLRequest) throws -> [String] {
        let params = try #require(try requestBody(request)["params"] as? [String: Any])
        return try #require(params["nullifiers"] as? [String])
    }

    /// Reads the nullifiers of every nullifier read that a transport recorded.
    ///
    /// - Parameter transport: The transport.
    /// - Returns: Each read's nullifiers, in request order.
    /// - Throws: A test prerequisite error if a read has no nullifiers.
    private static func nullifierReads(of transport: StubTransport) async throws -> [[String]] {
        try await transport.requests.filter { $0.url?.lastPathComponent == GetShieldedTransactionsByNullifiers.method }.map(nullifiers)
    }
}
