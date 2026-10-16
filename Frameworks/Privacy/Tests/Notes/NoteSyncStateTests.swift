import Encoding
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions

/// Verifies note syncs through the real Helius client with local indexer responses: the notes that
/// they find and drop, the reads that they send, and the states' encoding.
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

        /// Answers an indexer request from the contents.
        ///
        /// - Parameter request: A tag or nullifier read.
        /// - Returns: The read's only page.
        /// - Throws: A test prerequisite error if the request isn't an indexer read.
        func respond(to request: URLRequest) throws -> (Data, URLResponse) {
            switch try #require(request.url?.lastPathComponent) {
            case GetShieldedTransactionsByTags.method:
                return try reply(to: request, payload: IndexerResponses.page(transactions.map(IndexerResponses.row), in: "transactions", scanned: scanned))
            case GetEncryptedUtxosByTags.method:
                return try reply(to: request, payload: IndexerResponses.page(deposits.map(IndexerResponses.match), in: "matches", scanned: scanned))
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
        #expect(state.position == NoteSyncPosition(tags: [sender.signingAddress.bytes], transactionCursors: ["AQ=="], outputCursors: ["AQ=="]))
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
        #expect(state.position == NoteSyncPosition(tags: [sender.signingAddress.bytes], transactionCursors: ["Ag=="], outputCursors: ["Ag=="]))
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

    /// Verifies that a state with notes and a position decodes to itself.
    @Test
    func `States survive encoding`() async throws {
        let (state, _) = try await sync(NoteSyncState(), with: Indexer(transactions: [transfer], deposits: [deposit]))

        let decoded = try JSONDecoder().decode(NoteSyncState.self, from: JSONEncoder().encode(state))

        #expect(decoded == state)
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
