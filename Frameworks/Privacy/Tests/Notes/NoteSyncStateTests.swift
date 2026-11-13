import Encoding
import Foundation
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy
@testable import RPC

struct NoteSyncStateTests {
    private struct Indexer: Sendable {
        var earlier: [ShieldedTransaction] = []
        var transactions: [ShieldedTransaction] = []
        var deposits: [ShieldedTransaction] = []
        var forgedDeposits: [ShieldedTransaction] = []
        var spends: [ShieldedTransaction] = []
        var contextSlot: UInt64 = 1
        var outputTreeID: UInt16?
        var depositsPerPage: Int?
        var isFinalized = true
        var onChain: [String: String] = [:]

        func respond(to request: URLRequest) throws -> (Data, URLResponse) {
            if let signature = try NoteSyncStateTests.transactionRead(of: request), let result = onChain[signature] {
                return try reply(to: request, payload: #""result":\#(result)"#)
            }
            let rows = (earlier + transactions + spends).map(IndexerResponses.row) + deposits.map(IndexerResponses.match)
            let trees = UTXOTrees(rows: rows, forging: forgedDeposits.map(IndexerResponses.match), isFinalized: isFinalized)
            if let reply = try trees.respond(to: request) { return reply }
            switch try #require(request.url?.lastPathComponent) {
            case GetShieldedTransactionsByTags.method:
                let page = IndexerReplies.page(transactions.map(IndexerResponses.row), in: "events",
                                               contextSlot: contextSlot, outputTreeID: outputTreeID)
                return try reply(to: request, payload: #""result":\#(page)"#)
            case GetEncryptedUtxosByTags.method:
                let pages = PageCursor.pages(of: (deposits + forgedDeposits).map(IndexerResponses.match),
                                             perPage: depositsPerPage)
                let number = depositsPerPage == nil ? 0 : try PageCursor.page(of: request)
                let matches = try #require(pages.indices.contains(number) ? pages[number] : nil)
                let page = IndexerReplies.page(matches.rows, in: "outputs", next: matches.next, contextSlot: contextSlot,
                                               outputTreeID: outputTreeID)
                return try reply(to: request, payload: #""result":\#(page)"#)
            default:
                let requested = Set(try NoteSyncStateTests.nullifiers(of: request))
                let spending = spends.filter { $0.nullifiers.contains { requested.contains(Base58.encode($0)) } }
                let page = IndexerReplies.page(spending.map(IndexerResponses.row), in: "events", contextSlot: contextSlot)
                return try reply(to: request, payload: #""result":\#(page)"#)
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
        #expect(state.spendableLamports == 1_000_006)
        #expect(state.position == Self.caughtUpPosition(sender.viewTags, at: 1))
    }

    @Test
    func `Received notes count once their proofs lead to roots that their trees' accounts hold`() async throws {
        let (state, transport) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit, laterDeposit]))

        #expect(state.notes == (try notes(in: deposit) + notes(in: laterDeposit)))
        #expect(state.unconfirmedNotes.isEmpty)
        #expect(state.spendableLamports == 1_000_042)
        #expect(Set(try await Self.proofReads(of: transport)) == Set(state.notes.map { [Base58.encode($0.utxo.hash.bigEndianBytes)] }))
        #expect(try await Self.treeReads(of: transport) == 1)
    }

    @Test
    func `Notes whose roots aren't on chain yet count after a later sync finds them`() async throws {
        let (unconfirmed, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit], isFinalized: false))

        let (included, transport) = try await sync(unconfirmed, with: Indexer(earlier: [deposit]))

        #expect(unconfirmed.notes.isEmpty)
        #expect(unconfirmed.unconfirmedNotes == (try notes(in: deposit)))
        #expect(unconfirmed.hasUnconfirmedNotes)
        #expect(unconfirmed.spendableLamports == 0)
        #expect(included.notes == (try notes(in: deposit)))
        #expect(included.unconfirmedNotes.isEmpty)
        #expect(!included.hasUnconfirmedNotes)
        #expect(included.spendableLamports == 1_000_000)
        #expect(try await Self.proofReads(of: transport) == [[Base58.encode(try notes(in: deposit)[0].utxo.hash.bigEndianBytes)]])
    }

    @Test
    func `Notes whose proofs don't lead to their roots are dropped`() async throws {
        let (state, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit], forgedDeposits: [laterDeposit]))

        let (later, transport) = try await sync(state, with: Indexer(earlier: [deposit]))

        #expect(state.notes == (try notes(in: deposit)))
        #expect(state.unconfirmedNotes.isEmpty)
        #expect(state.spendableLamports == 1_000_000)
        #expect(later == state)
        #expect(try await Self.proofReads(of: transport).isEmpty)
    }

    @Test
    func `Spent unconfirmed notes are dropped`() async throws {
        let (unconfirmed, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit], isFinalized: false))
        let spender = spend(of: unconfirmed.unconfirmedNotes)

        let indexer = Indexer(earlier: [deposit], spends: [spender], onChain: [spender.signature: "null"])

        let (state, transport) = try await sync(unconfirmed, with: indexer)

        #expect(state.notes.isEmpty)
        #expect(state.unconfirmedNotes.isEmpty)
        #expect(try await Self.nullifierReads(of: transport) == [unconfirmed.unconfirmedNotes.map { Base58.encode($0.nullifier.bigEndianBytes) }])
        #expect(try await Self.transactionReads(of: transport).isEmpty)
    }

    @Test
    func `Resumed syncs read after the stored position`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))

        let (state, transport) = try await sync(first, with: Indexer(deposits: [laterDeposit], contextSlot: 2))

        let filters = try await Self.tagReads(of: transport)
            .map { try #require(try requestBody($0)["params"] as? [String: Any])["filters"] as? [String: [String: Int]] }
        #expect(filters == [["slot": ["gt": 1]], ["slot": ["gt": 1]]])
        #expect(state.notes == (try notes(in: deposit) + notes(in: laterDeposit)))
        #expect(state.position == Self.caughtUpPosition(sender.viewTags, at: 2))
    }

    @Test
    func `Spends of stored notes drop them`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))

        let (state, _) = try await sync(first, with: Indexer(spends: [spend(of: first.notes)]))

        #expect(state.notes.isEmpty)
        #expect(state.spendableLamports == 0)
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
        #expect(try await Self.transactionReads(of: transport).isEmpty)
    }

    @Test
    func `Confirmed spend claims drop the note after one read of their transaction`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: first.notes)

        let (state, transport) = try await sync(first, with: Indexer(transactions: [spender], spends: [spender]))

        #expect(state.notes.isEmpty)
        #expect(state.spendableLamports == 0)
        #expect(try await Self.transactionReads(of: transport) == [spender.signature])
    }

    @Test
    func `Spend claims whose transaction isn't visible yet hide the note until a later sync confirms them`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: first.notes)

        let (unconfirmed, _) = try await sync(first, with: Indexer(spends: [spender], onChain: [spender.signature: "null"]))
        let (confirmed, transport) = try await sync(unconfirmed, with: Indexer(spends: [spender]))

        #expect(unconfirmed.notes == first.notes)
        #expect(unconfirmed.claimedSpends == Set(first.notes.map(\.nullifier.bigEndianBytes)))
        #expect(unconfirmed.spendableLamports == 0)
        #expect(confirmed.notes.isEmpty)
        #expect(confirmed.claimedSpends.isEmpty)
        #expect(confirmed.spendableLamports == 0)
        #expect(try await Self.transactionReads(of: transport) == [spender.signature])
    }

    @Test
    func `Spend claims whose transaction failed keep the note`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: first.notes)
        let failed = SpendTransactions.result(spending: spender.nullifiers, error: SpendTransactions.failure)

        let (state, _) = try await sync(first, with: Indexer(spends: [spender], onChain: [spender.signature: failed]))

        #expect(state.notes == first.notes)
        #expect(state.claimedSpends.isEmpty)
        #expect(state.spendableLamports == 1_000_000)
        #expect(state.rejectedSpends == [spender.signature])
    }

    @Test
    func `Spend claims whose transaction spends other nullifiers keep the note`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: first.notes)
        let unrelated = SpendTransactions.result(spending: [[UInt8](repeating: 9, count: 32)])

        let (state, _) = try await sync(first, with: Indexer(spends: [spender], onChain: [spender.signature: unrelated]))

        #expect(state.notes == first.notes)
        #expect(state.claimedSpends.isEmpty)
        #expect(state.spendableLamports == 1_000_000)
        #expect(state.rejectedSpends == [spender.signature])
    }

    @Test
    func `Refuted spend claims aren't read again until no claim names them`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: first.notes)
        let unrelated = SpendTransactions.result(spending: [[UInt8](repeating: 9, count: 32)])
        let indexer = Indexer(spends: [spender], onChain: [spender.signature: unrelated])
        let (refuted, _) = try await sync(first, with: indexer)

        let (named, namedTransport) = try await sync(refuted, with: indexer)
        let (forgotten, _) = try await sync(named, with: Indexer())

        #expect(try await Self.transactionReads(of: namedTransport).isEmpty)
        #expect(named.rejectedSpends == [spender.signature])
        #expect(named.notes == first.notes)
        #expect(forgotten.rejectedSpends.isEmpty)
        #expect(forgotten.notes == first.notes)
    }

    @Test
    func `Spend claims whose transaction ten reads in a row don't find count as refuted`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: first.notes)
        let indexer = Indexer(spends: [spender], onChain: [spender.signature: "null"])
        var waiting = first
        for _ in 0..<9 {
            waiting = try await sync(waiting, with: indexer).0
        }

        let (refuted, transport) = try await sync(waiting, with: indexer)
        let (later, laterTransport) = try await sync(refuted, with: indexer)

        #expect(waiting.rejectedSpends.isEmpty)
        #expect(waiting.notes == first.notes)
        #expect(waiting.spendableLamports == 0)
        #expect(try await Self.transactionReads(of: transport) == [spender.signature])
        #expect(refuted.rejectedSpends == [spender.signature])
        #expect(refuted.notes == first.notes)
        #expect(refuted.spendableLamports == 1_000_000)
        #expect(try await Self.transactionReads(of: laterTransport).isEmpty)
        #expect(later.notes == first.notes)
    }

    @Test
    func `Missing reads of a spend claim are saved until no claim names it`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: first.notes)

        let (missing, _) = try await sync(first, with: Indexer(spends: [spender], onChain: [spender.signature: "null"]))
        let decoded = try JSONDecoder().decode(NoteSyncState.self, from: JSONEncoder().encode(missing))
        let (forgotten, _) = try await sync(decoded, with: Indexer())

        #expect(decoded.missingSpendReads == [spender.signature: 1])
        #expect(forgotten.missingSpendReads.isEmpty)
        #expect(forgotten.notes == first.notes)
    }

    @Test
    func `A successful spend claim with spend data of an unknown layout fails the sync`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: first.notes)
        let data = Array(SpendTransactions.transactData(spending: spender.nullifiers).dropLast())
        let unknown = SpendTransactions.result(of: [(SpendTransactions.program, data)])

        await #expect(throws: ShieldedPool.InstructionError.unknownLayout) {
            try await sync(first, with: Indexer(spends: [spender], onChain: [spender.signature: unknown]))
        }
    }

    @Test
    func `One claim per nullifier is read in a sync, the oldest first`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let older = spend(of: first.notes, signature: 8, slot: 15)
        let newer = spend(of: first.notes, signature: 7, slot: 16)
        let unrelated = SpendTransactions.result(spending: [[UInt8](repeating: 9, count: 32)])
        let indexer = Indexer(spends: [newer, older], onChain: [older.signature: unrelated])

        let (refuted, firstTransport) = try await sync(first, with: indexer)
        let (confirmed, secondTransport) = try await sync(refuted, with: indexer)

        #expect(try await Self.transactionReads(of: firstTransport) == [older.signature])
        #expect(refuted.notes == first.notes)
        #expect(try await Self.transactionReads(of: secondTransport) == [newer.signature])
        #expect(confirmed.notes.isEmpty)
    }

    @Test
    func `A sync reads at most eight claimed spends, the oldest first, and a later sync reads the rest`() async throws {
        let counted = (0..<10).map { NoteFixtures.note(at: UInt8($0)) }
        let state = try NoteSyncState(
            position: nil, notes: counted, unconfirmedNotes: [], outputTreeID: nil, pending: [], localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )
        let spenders = counted.enumerated().map { index, note in
            spend(of: [note], signature: UInt8(40 + index), slot: UInt64(100 - index))
        }
        let oldest = spenders.sorted { $0.slot < $1.slot }.map(\.signature)

        let (first, firstTransport) = try await sync(state, with: Indexer(spends: spenders))
        let (second, secondTransport) = try await sync(first, with: Indexer(spends: spenders))

        #expect(try await Self.transactionReads(of: firstTransport).sorted() == Array(oldest.prefix(8)).sorted())
        #expect(first.notes == Array(counted.prefix(2)))
        #expect(try await Self.transactionReads(of: secondTransport).sorted() == Array(oldest.suffix(2)).sorted())
        #expect(second.notes.isEmpty)
    }

    @Test
    func `Syncs to the end read each claimed spend once across their batches`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let held = try NoteSyncState(
            position: nil, notes: first.notes, unconfirmedNotes: [], outputTreeID: nil, pending: [], localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )
        let spender = spend(of: first.notes)
        let indexer = Indexer(
            deposits: Array(repeating: foreignDeposit, count: 9), spends: [spender], depositsPerPage: 1,
            onChain: [spender.signature: "null"]
        )
        let transport = StubTransport { try indexer.respond(to: $0) }

        let state = try await held.syncedToEnd(for: sender, rpc: SolanaRPC.devnet(transport: transport), indexer: Self.indexer(transport))

        #expect(state.notes == first.notes)
        #expect(state.missingSpendReads == [spender.signature: 1])
        #expect(try await Self.nullifierReads(of: transport).count > 1)
        #expect(try await Self.transactionReads(of: transport) == [spender.signature])
    }

    @Test
    func `Forged spend claims in the tag stream keep stored notes`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let forged = spend(of: first.notes)
        let unrelated = SpendTransactions.result(spending: [[UInt8](repeating: 9, count: 32)])

        let (state, _) = try await sync(first, with: Indexer(transactions: [forged], onChain: [forged.signature: unrelated]))

        #expect(state.notes == first.notes)
        #expect(state.spendableLamports == 1_000_000)
    }

    @Test
    func `Spend claims about notes received in the same batch drop them without a transaction read`() async throws {
        let spender = spend(of: try notes(in: deposit))
        let unrelated = SpendTransactions.result(spending: [[UInt8](repeating: 9, count: 32)])
        let indexer = Indexer(transactions: [spender], deposits: [deposit], onChain: [spender.signature: unrelated])

        let (state, transport) = try await sync(NoteSyncState(), with: indexer)

        #expect(state.notes.isEmpty)
        #expect(state.unconfirmedNotes.isEmpty)
        #expect(state.spendableLamports == 0)
        #expect(try await Self.transactionReads(of: transport).isEmpty)
        #expect(try await Self.proofReads(of: transport).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Claimed spends' transactions are read at once`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit, laterDeposit]))
        let spenders = [spend(of: [first.notes[0]], signature: 7), spend(of: [first.notes[1]], signature: 8)]
        let (firstRead, firstContinuation) = AsyncStream.makeStream(of: Void.self)
        let (secondRead, secondContinuation) = AsyncStream.makeStream(of: Void.self)
        let indexer = Indexer(spends: spenders)
        let transport = StubTransport { request in
            switch try Self.transactionRead(of: request) {
            case spenders[0].signature?:
                firstContinuation.yield()
                var signals = secondRead.makeAsyncIterator()
                await signals.next()
            case spenders[1].signature?:
                secondContinuation.yield()
                var signals = firstRead.makeAsyncIterator()
                await signals.next()
            default:
                break
            }
            return try indexer.respond(to: request)
        }

        let state = try await first.synced(for: sender, rpc: SolanaRPC.devnet(transport: transport), indexer: Self.indexer(transport))

        #expect(state.notes.isEmpty)
        #expect(Set(try await Self.transactionReads(of: transport)) == Set(spenders.map(\.signature)))
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
    func `A backlog longer than one read syncs over several syncs`() async throws {
        let indexer = Indexer(deposits: Array(repeating: foreignDeposit, count: 8) + [deposit], depositsPerPage: 1)

        let (first, _) = try await sync(NoteSyncState(), with: indexer)
        let (second, _) = try await sync(first, with: indexer)

        let tags = sender.viewTags
        #expect(first.notes.isEmpty)
        let resumed = IndexerCheckpoint(afterSlot: nil, paginationToken: PageCursor.cursor(forPage: 8))
        #expect(first.position == NoteSyncPosition(tags: tags, transactionCheckpoints: [Self.caughtUp(at: 1)],
                                                   outputCheckpoints: [resumed]))
        #expect(second.notes == (try notes(in: deposit)))
        #expect(second.position == Self.caughtUpPosition(tags, at: 1))
    }

    @Test
    func `Syncs to the end read every batch of a backlog`() async throws {
        let indexer = Indexer(deposits: Array(repeating: foreignDeposit, count: 8) + [deposit], depositsPerPage: 1)
        let transport = StubTransport { try indexer.respond(to: $0) }

        let state = try await NoteSyncState().syncedToEnd(for: sender, rpc: SolanaRPC.devnet(transport: transport), indexer: Self.indexer(transport))

        #expect(state.notes == (try notes(in: deposit)))
        #expect(state.position == Self.caughtUpPosition(sender.viewTags, at: 1))
    }

    @Test
    func `A sync to the end that doesn't end within 128 batches fails`() async throws {
        let filler = IndexerResponses.match(foreignDeposit)
        let transport = StubTransport { request in
            guard request.url?.lastPathComponent == GetEncryptedUtxosByTags.method else {
                return try Indexer().respond(to: request)
            }
            let next = PageCursor.cursor(forPage: try PageCursor.page(of: request) + 1)
            return try reply(to: request, payload: #""result":\#(IndexerReplies.page([filler], in: "outputs", next: next))"#)
        }
        await #expect(throws: RPCError.invalidResponse(.endlessStream)) {
            try await NoteSyncState().syncedToEnd(for: sender, rpc: SolanaRPC.devnet(transport: transport), indexer: Self.indexer(transport))
        }
        let routes = await transport.requests.map { $0.url?.lastPathComponent }
        #expect(routes.filter { $0 == GetShieldedTransactionsByTags.method }.count == 128)
    }

    @Test
    func `Totals beyond 64 bits fail the sync`() async throws {
        let largest = try largestState()

        await #expect(throws: NoteSyncState.ValidationError.amountOverflow) {
            try await sync(largest, with: Indexer(deposits: [deposit]))
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

        let state = try await first.synced(for: sender, rpc: SolanaRPC.devnet(transport: transport), indexer: Self.indexer(transport))

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

        let state = try await first.synced(for: sender, rpc: SolanaRPC.devnet(transport: transport), indexer: Self.indexer(transport))

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
            try await first.synced(for: sender, rpc: SolanaRPC.devnet(transport: transport), indexer: Self.indexer(transport))
        }
        #expect(await transport.observedCancellation)
    }

    @Test
    func `Syncs read the signing and viewing key tags`() async throws {
        let record = try #require(try RegistryVectors.load().records.first { $0.owner == TransferVectors.senderSigningAddress })
        let viewingTag = Array(try fixtureBytes(record.viewingPublicKey).dropFirst())

        let (_, transport) = try await sync(NoteSyncState(), with: Indexer())

        let tags = try await Self.tagReads(of: transport)
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
        #expect(state.spendableLamports == 42)
    }

    @Test
    func `Recorded token spends keep their change pending in their token`() throws {
        let vector = try #require(try DepositNoteVectors.load().deposits.first)
        let token = try vector.transaction(signature: IndexerResponses.signature(9), mint: ConfidentialPlaintext.Asset.usdc.mint)
        let held = try NoteSyncState(
            position: nil, notes: notes(in: token), unconfirmedNotes: [], outputTreeID: nil, pending: [], localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )

        let state = try held.recording(privateSpend(of: held.notes, receiving: 5, asset: .usdc), signature: IndexerResponses.signature(8))

        #expect(state.notes.isEmpty)
        #expect(state.pendingAmount(of: .usdc) == 5)
        #expect(state.pendingLamports == 0)
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
    func `Recorded spends of claimed notes end their claims`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let spender = spend(of: first.notes)
        let (claimed, _) = try await sync(first, with: Indexer(spends: [spender], onChain: [spender.signature: "null"]))

        let state = try claimed.recording(privateSpend(of: first.notes, receiving: 0), signature: spender.signature)

        #expect(state.notes.isEmpty)
        #expect(state.claimedSpends.isEmpty)
        #expect(state.localSpends == claimed.claimedSpends)
    }

    @Test
    func `Pending amounts end when the batch returns their transaction`() async throws {
        let recorded = try NoteSyncState().recording(depositOf: 1_000_000, signature: deposit.signature)

        let (unreported, _) = try await sync(recorded, with: Indexer())
        let (reported, _) = try await sync(unreported, with: Indexer(deposits: [deposit]))

        #expect(recorded.notes.isEmpty)
        #expect(recorded.pendingLamports == 1_000_000)
        #expect(unreported.pendingLamports == 1_000_000)
        #expect(reported.pendingLamports == 0)
        #expect(reported.notes == (try notes(in: deposit)))
        #expect(reported.spendableLamports == 1_000_000)
    }

    @Test
    func `Pending amounts stay until their transaction's notes are included`() async throws {
        let recorded = try NoteSyncState().recording(depositOf: 1_000_000, signature: deposit.signature)

        let (unconfirmed, _) = try await sync(recorded, with: Indexer(deposits: [deposit], isFinalized: false))
        let (included, _) = try await sync(unconfirmed, with: Indexer(earlier: [deposit]))

        #expect(unconfirmed.notes.isEmpty)
        #expect(unconfirmed.pendingLamports == 1_000_000)
        #expect(unconfirmed.spendableLamports == 0)
        #expect(included.notes == (try notes(in: deposit)))
        #expect(included.pendingLamports == 0)
        #expect(included.spendableLamports == 1_000_000)
    }

    @Test
    func `Pending amounts end when their transaction's notes are spent in the same batch`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let recorded = try first.recording(privateSpend(of: first.notes, receiving: 6), signature: transfer.signature)

        let (state, transport) = try await sync(recorded, with: Indexer(transactions: [transfer, spend(of: notes(in: transfer))]))

        #expect(recorded.pendingLamports == 6)
        #expect(state.notes.isEmpty)
        #expect(state.pendingLamports == 0)
        #expect(state.spendableLamports == 0)
        #expect(try await Self.proofReads(of: transport).isEmpty)
    }

    @Test
    func `Pending amounts end when a claimed spend of their transaction's unconfirmed notes is accepted without a read`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let recorded = try first.recording(privateSpend(of: first.notes, receiving: 6), signature: transfer.signature)
        let spender = spend(of: try notes(in: transfer))
        let (held, _) = try await sync(recorded, with: Indexer(transactions: [transfer], isFinalized: false))

        let (claimed, transport) = try await sync(
            held, with: Indexer(earlier: [transfer], spends: [spender], isFinalized: false, onChain: [spender.signature: "null"])
        )

        #expect(held.unconfirmedNotes == (try notes(in: transfer)))
        #expect(held.pendingLamports == 6)
        #expect(claimed.unconfirmedNotes.isEmpty)
        #expect(claimed.pendingLamports == 0)
        #expect(claimed.spendableLamports == 0)
        #expect(try await Self.transactionReads(of: transport).isEmpty)
    }

    @Test
    func `Recorded deposits are counted once`() async throws {
        let (synced, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))

        let afterSync = try synced.recording(depositOf: 1_000_000, signature: deposit.signature)
        let twice = try NoteSyncState().recording(depositOf: 1_000_000, signature: deposit.signature)
            .recording(depositOf: 1_000_000, signature: deposit.signature)

        #expect(afterSync.pendingLamports == 0)
        #expect(afterSync.spendableLamports == 1_000_000)
        #expect(twice.pendingLamports == 1_000_000)
        #expect(twice.spendableLamports == 0)
    }

    @Test
    func `Recorded spends count their change once`() async throws {
        let (synced, _) = try await sync(NoteSyncState(), with: Indexer(transactions: [transfer], deposits: [deposit]))
        let spend = try privateSpend(of: notes(in: deposit), receiving: 6)

        let afterSync = try synced.recording(spend, signature: transfer.signature)
        let twice = try synced.recording(privateSpend(of: notes(in: deposit), receiving: 5), signature: IndexerResponses.signature(8))
            .recording(privateSpend(of: notes(in: deposit), receiving: 5), signature: IndexerResponses.signature(8))

        #expect(afterSync.pendingLamports == 0)
        #expect(afterSync.spendableLamports == 6)
        #expect(twice.pendingLamports == 5)
        #expect(twice.spendableLamports == 6)
    }

    @Test
    func `Spends recorded after their notes are gone add nothing pending`() async throws {
        let (synced, _) = try await sync(NoteSyncState(), with: Indexer(transactions: [transfer]))
        let (respent, _) = try await sync(synced, with: Indexer(transactions: [transfer], spends: [spend(of: synced.notes)]))
        let spent = try transfer.nullifiers.prefix(1).map { try #require(Poseidon.Element(bigEndianBytes: $0)) }
        let spend = PrivateSpend(
            instruction: Instruction(program: try ShieldedPool.address), amount: 4, receivedAmount: 6, treeIDs: [0],
            nullifiers: spent, asset: .sol
        )

        let state = try respent.recording(spend, signature: transfer.signature)

        #expect(synced.spendableLamports == 6)
        #expect(respent.notes.isEmpty)
        #expect(state.pendingLamports == 0)
        #expect(state.spendableLamports == 0)
    }

    @Test
    func `Pending amounts end when a kept note comes from their transaction`() async throws {
        let (synced, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit]))
        let pending = try NoteSyncState(
            position: synced.position, notes: synced.notes, unconfirmedNotes: [], outputTreeID: nil,
            pending: [PendingAmount(signature: deposit.signature, asset: .sol, amount: 1_000_000)],
            localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )

        let (state, _) = try await sync(pending, with: Indexer())

        #expect(state.pendingLamports == 0)
        #expect(state.spendableLamports == 1_000_000)
    }

    @Test
    func `Zero-lamport deposits can't be recorded`() {
        #expect(throws: ValidationError.invalidAmount) {
            try NoteSyncState().recording(depositOf: 0, signature: IndexerResponses.signature(8))
        }
    }

    @Test
    func `Token notes count only toward their own token`() throws {
        let vector = try #require(try DepositNoteVectors.load().deposits.first)
        let token = try vector.transaction(signature: IndexerResponses.signature(9), mint: ConfidentialPlaintext.Asset.usdc.mint)
        let state = try NoteSyncState(
            position: nil, notes: notes(in: deposit) + notes(in: token), unconfirmedNotes: [], outputTreeID: nil, pending: [],
            localSpends: [], claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )

        #expect(state.spendableLamports == (try notes(in: deposit).reduce(0) { $0 + $1.amount }))
        #expect(state.spendableAmount(of: .usdc) == (try notes(in: token).reduce(0) { $0 + $1.amount }))
        #expect(state.spendableAmount(of: .usdt) == 0)
    }

    @Test
    func `Recorded token deposits stay pending in their token`() throws {
        let state = try NoteSyncState().recording(depositOf: 7, of: .usdc, signature: IndexerResponses.signature(8))

        #expect(state.pendingAmount(of: .usdc) == 7)
        #expect(state.pendingAmount(of: .usdt) == 0)
        #expect(state.pendingLamports == 0)
    }

    @Test
    func `Each asset's total has its own 64 bits`() throws {
        let largest = try largestState()
        let token = try #require(try DepositNoteVectors.load().deposits.first)
            .transaction(signature: IndexerResponses.signature(9), mint: ConfidentialPlaintext.Asset.usdc.mint)

        let state = try NoteSyncState(
            position: nil, notes: largest.notes + notes(in: token), unconfirmedNotes: [], outputTreeID: nil, pending: [],
            localSpends: [], claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )

        #expect(state.spendableLamports == largest.spendableLamports)
    }

    @Test
    func `Records beyond 64 bits are rejected`() throws {
        let largest = try largestState()

        #expect(throws: NoteSyncState.ValidationError.amountOverflow) {
            try largest.recording(depositOf: 1_000_000, signature: IndexerResponses.signature(8))
        }
    }

    @Test(arguments: [true, false])
    func `States survive encoding`(isFinalized: Bool) async throws {
        let indexer = Indexer(transactions: [transfer], deposits: [deposit], isFinalized: isFinalized)
        let (state, _) = try await sync(NoteSyncState(), with: indexer)

        let decoded = try JSONDecoder().decode(NoteSyncState.self, from: JSONEncoder().encode(state))

        #expect(decoded == state)
        #expect(decoded.notes.isEmpty == !isFinalized)
        #expect(decoded.unconfirmedNotes.isEmpty == isFinalized)
    }

    @Test
    func `Recorded states survive encoding`() async throws {
        let (first, _) = try await sync(NoteSyncState(), with: Indexer(deposits: [deposit, laterDeposit]))
        let spender = spend(of: try notes(in: laterDeposit))
        let (claimed, _) = try await sync(first, with: Indexer(spends: [spender], outputTreeID: 2, onChain: [spender.signature: "null"]))
        let state = try claimed.recording(privateSpend(of: notes(in: deposit), receiving: 5), signature: IndexerResponses.signature(8))

        let decoded = try JSONDecoder().decode(NoteSyncState.self, from: JSONEncoder().encode(state))

        #expect(decoded == state)
        #expect(decoded.outputTreeID == 2)
        #expect(decoded.pendingLamports == 5)
        #expect(!decoded.localSpends.isEmpty)
        #expect(!decoded.claimedSpends.isEmpty)
    }

    @Test(arguments: [
        "notes", "unconfirmedNotes", "outputTreeID", "pending", "localSpends", "claimedSpends", "rejectedSpends", "missingSpendReads",
    ])
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

    @Test(arguments: ["localSpends", "claimedSpends"])
    func `Encoded nullifiers of another length are rejected`(key: String) throws {
        var fields = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteSyncState())) as? [String: Any])
        fields[key] = [Data(repeating: 1, count: 31).base64EncodedString()]
        let encoded = try JSONSerialization.data(withJSONObject: fields)

        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(NoteSyncState.self, from: encoded)
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected corrupted data, not \(String(describing: error)).")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == [key])
    }

    @Test
    func `Encoded totals beyond 64 bits are rejected`() async throws {
        let largest = try largestState()
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

    private func sync(_ state: NoteSyncState, with indexer: Indexer) async throws -> (NoteSyncState, StubTransport) {
        let transport = StubTransport { try indexer.respond(to: $0) }
        let synced = try await state.synced(for: sender, rpc: SolanaRPC.devnet(transport: transport), indexer: Self.indexer(transport))
        return (synced, transport)
    }

    private func largestState() throws -> NoteSyncState {
        try NoteSyncState(
            position: nil, notes: notes(in: largestDeposit), unconfirmedNotes: [], outputTreeID: nil, pending: [], localSpends: [],
            claimedSpends: [], rejectedSpends: [], missingSpendReads: [:]
        )
    }

    private func notes(in transaction: ShieldedTransaction) throws -> [ReceivedNote] {
        try ReceivedNote.notes(in: transaction, of: sender)
    }

    private func spend(of notes: [ReceivedNote], signature: UInt8 = 7, slot: UInt64 = 20) -> ShieldedTransaction {
        ShieldedTransaction(
            signature: IndexerResponses.signature(signature), slot: slot, eventIndex: 0, transactionViewingKey: nil, salt: nil, outputs: [],
            nullifiers: notes.map(\.nullifier.bigEndianBytes), isProofless: false
        )
    }

    private func privateSpend(
        of notes: [ReceivedNote], receiving lamports: UInt64, asset: ConfidentialPlaintext.Asset = .sol
    ) throws -> PrivateSpend {
        PrivateSpend(
            instruction: Instruction(program: try ShieldedPool.address), amount: 1, receivedAmount: lamports,
            treeIDs: [0], nullifiers: notes.map(\.nullifier), asset: asset
        )
    }

    private static func transactionRead(of request: URLRequest) throws -> String? {
        let body = try requestBody(request)
        guard body["method"] as? String == GetTransaction.method else { return nil }
        return try #require((body["params"] as? [Any])?.first as? String)
    }

    private static func transactionReads(of transport: StubTransport) async throws -> [String] {
        try await transport.requests.compactMap(transactionRead(of:))
    }

    private static func nullifiers(of request: URLRequest) throws -> [String] {
        let params = try #require(try requestBody(request)["params"] as? [String: Any])
        return try #require(params["nullifiers"] as? [String])
    }

    private static func nullifierReads(of transport: StubTransport) async throws -> [[String]] {
        try await transport.requests.filter { $0.url?.lastPathComponent == GetShieldedTransactionsByNullifiers.method }.map(nullifiers)
    }

    private static func proofReads(of transport: StubTransport) async throws -> [[String]] {
        try await transport.requests.filter { $0.url?.lastPathComponent == GetMerkleProofs.method }.map {
            try MerkleProofReplies.requestedLeaves(in: $0).leaves
        }
    }

    private static func treeReads(of transport: StubTransport) async throws -> Int {
        try await transport.requests.count { try requestBody($0)["method"] as? String == GetMultipleAccounts.method }
    }

    private static func caughtUp(at slot: UInt64) -> IndexerCheckpoint {
        IndexerCheckpoint(afterSlot: slot, paginationToken: nil)
    }

    private static func caughtUpPosition(_ tags: [[UInt8]], at slot: UInt64) -> NoteSyncPosition {
        NoteSyncPosition(tags: tags, transactionCheckpoints: [caughtUp(at: slot)], outputCheckpoints: [caughtUp(at: slot)])
    }

    private static func tagReads(of transport: StubTransport) async -> [URLRequest] {
        await transport.requests.filter {
            [GetShieldedTransactionsByTags.method, GetEncryptedUtxosByTags.method].contains($0.url?.lastPathComponent)
        }
    }

    private static func indexer(_ transport: StubTransport) -> Zolana {
        Zolana.devnet(transport: transport)
    }
}
