import Foundation
@testable import RPC
import Storage
import Testing
import Transactions
@testable import widgets

/// Verifies sending, recording, and watching through the real transaction coordinator, with local responses and
/// sockets, and in-memory records.
///
/// Each transaction pays 1 SOL from the fixture account on devnet; its blockhash is valid through block height 550.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionStoreTests {
    /// A provider's rate limit.
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    /// The store, its records, and the local responses and connections behind it.
    private struct Sending {
        /// The store under test.
        let store: TransactionStore
        /// The in-memory records of the fixture account on devnet.
        let records: StoredValue<[TransactionRecord]>
        /// The account that sends.
        let account: widgets.Account
        /// The payment's recipient.
        let recipient: Address
        /// The responses that acknowledge each sent transaction.
        let sent: HTTPResponses
        /// The connections of the coordinator's watch.
        let sockets: SocketSequence

        /// The account's records on devnet.
        var key: TransactionRecord.Key { TransactionRecord.Key(account: account.id, network: .devnet) }

        /// The payment that the fixture sends.
        var payment: TransactionRecord.Kind { .payment(recipient: recipient, mint: nil, units: 1_000_000_000) }

        /// Simulates the payment for review.
        /// - Returns: The simulation to send.
        /// - Throws: A simulation error.
        func simulate() async throws -> Simulation {
            try await store.coordinator(for: .devnet).transfer(1_000_000_000, using: account, to: recipient)
        }

        /// Simulates and sends the payment.
        /// - Parameter settling: What finishes the payment's work once it settles, if anything.
        /// - Returns: The pending record.
        /// - Throws: A simulation or sending error.
        func send(settling: (any TransactionSettling)? = nil) async throws -> TransactionRecord {
            try await store.send(simulate(), as: payment, from: account, settling: settling)
        }

        /// Waits for a sent record to settle, then for its watch's connections to close.
        /// - Parameter record: The sent record.
        /// - Returns: The settled status.
        /// - Throws: The watch's error.
        func settle(_ record: TransactionRecord) async throws -> TransactionRecord.Status {
            let status = try await store.watch(record.id, for: key)
            await sockets.waitUntilClosed()
            return status
        }

        /// Whether the in-memory records are exactly one record.
        /// - Parameter record: The record.
        /// - Returns: Whether it's the only saved record.
        func savedOnly(_ record: TransactionRecord) async -> Bool {
            await records.value?.map(\.id) == [record.id]
        }
    }

    // MARK: Sending

    /// A sent payment is saved as a pending record of what it pays, and its watch saves how it settled.
    @Test
    func `A sent payment is saved as pending`() async throws {
        let sending = try Self.sending()

        let record = try await sending.send()

        #expect(record.status == .pending)
        #expect(record.settled == nil)
        #expect(record.kind == sending.payment)
        #expect(record.key == sending.key)
        #expect(record.lastValidBlockHeight == 550)
        #expect(await sending.savedOnly(record))
        #expect(try await sending.settle(record) == .succeeded)
    }

    /// A cancelled authentication records and sends nothing.
    @Test
    func `A cancelled authentication records nothing`() async throws {
        let sending = try Self.sending(recovery: SigningRecoveryStore(recovery: try SigningFixture().recovery,
                                                                      error: CancellationError()))

        await #expect(throws: CancellationError.self) { try await sending.send() }

        await Self.expectNothingSent(by: sending)
    }

    /// A payment that can't be signed records and sends nothing.
    @Test
    func `A payment that can't be signed records nothing`() async throws {
        let sending = try Self.sending(recovery: SigningRecoveryStore(recovery: try SigningFixture().recovery,
                                                                      error: CocoaError(.fileReadUnknown)))

        await #expect(throws: CocoaError(.fileReadUnknown)) { try await sending.send() }

        await Self.expectNothingSent(by: sending)
    }

    /// A payment whose delivery is unknown after signing, such as after a rate limit, is still recorded and watched,
    /// since it may land.
    @Test
    func `A payment with unknown delivery is recorded and watched`() async throws {
        let sending = try Self.sending(sent: HTTPResponses([:], error: Self.rateLimit))

        let record = try await sending.send()

        #expect(record.status == .pending)
        #expect(await sending.savedOnly(record))
        #expect(try await sending.settle(record) == .succeeded)
    }

    /// Cancelling the caller while the payment is being sent doesn't stop its delivery, its record, or its watch.
    @Test
    func `Cancelling the caller doesn't stop delivery`() async throws {
        let gate = Suspension()
        let sending = try Self.sending(sent: .sending(gate: gate))
        let simulation = try await sending.simulate()
        let caller = Task { try await sending.store.send(simulation, as: sending.payment, from: sending.account) }
        await gate.waitUntilStarted()

        caller.cancel()
        gate.resume()
        let record = try await caller.value

        #expect(await !sending.sent.wasCancelled)
        #expect(await sending.savedOnly(record))
        #expect(try await sending.settle(record) == .succeeded)
    }

    /// Only the latest 200 records are kept: a new one goes first and the oldest is forgotten.
    @Test
    func `Only the latest 200 records are kept`() async throws {
        let fixture = try SigningFixture()
        let saved = try (0..<200).map {
            try TransactionRecord.fixture(Self.payment(), signature: "saved-\($0)", account: fixture.account.id)
        }
        let sending = try Self.sending(fixture: fixture, records: StoredValue(saved))

        let record = try await sending.send()

        let kept = try #require(await sending.records.value)
        #expect(kept.count == 200)
        #expect(kept.first?.id == record.id)
        #expect(kept.last?.id == "saved-198")
        #expect(sending.store.records(for: sending.key).map(\.id) == kept.map(\.id))
        _ = try await sending.settle(record)
    }

    // MARK: Watching

    /// A settled watch saves the status of its outcome and when it was found.
    /// - Parameters:
    ///   - status: The status read, or `nil` when the provider has none.
    ///   - height: The finalized block height of the watch's epoch reads.
    ///   - expected: The saved status.
    @Test(arguments: [
        (GetSignatureStatuses.Response.status(.finalized), UInt64(500), TransactionRecord.Status.succeeded),
        (.status(.finalized, error: TransactionError(name: "InstructionError", details: nil)), 500, .failed),
        // The block height is past the blockhash's last valid one, and no status exists.
        (.status(nil), 600, .dropped),
    ])
    func `A settled watch saves its outcome`(status: GetSignatureStatuses.Response, height: UInt64,
                                             expected: TransactionRecord.Status) async throws {
        let sending = try Self.sending(statuses: [status], height: height)
        let record = try await sending.send()

        let settled = try await sending.settle(record)

        #expect(settled == expected)
        let saved = try #require(await sending.records.value?.first)
        #expect(saved.status == expected)
        #expect(try #require(saved.settled) >= saved.created)
        #expect(sending.store.record(record.id, for: sending.key) == saved)
    }

    /// The settling runs once, after the outcome is saved, and the settled count increases only after it.
    @Test
    func `The settling runs once after the outcome is saved`() async throws {
        let sending = try Self.sending()
        let settling = RecordingSettling(records: sending.records, store: sending.store, key: sending.key)
        let record = try await sending.send(settling: settling)

        _ = try await sending.settle(record)
        _ = try await sending.settle(record)

        let expected = RecordingSettling.Call(signature: record.id, saved: .succeeded, settledCount: 0)
        #expect(await settling.calls == [expected])
        #expect(sending.store.settledCount(for: sending.key) == 1)
    }

    /// A watch that stops, even before anyone waits for it, gives its error to the next caller and leaves the record
    /// pending without settling it; watching again settles it.
    @Test
    func `A stopped watch reports its error once and can watch again`() async throws {
        let refusal = Self.rateLimit
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let sending = try Self.sending(sockets: sockets)
        let record = try await sending.send()
        for await _ in sockets.openings { break }

        await #expect(throws: DeliveryError.self) { try await sending.store.watch(record.id, for: sending.key) }
        #expect(await sending.records.value?.first?.status == .pending)
        #expect(sending.store.settledCount(for: sending.key) == 0)

        #expect(try await sending.settle(record) == .succeeded)
        #expect(sockets.sockets.count == 2)
    }

    /// Cancelling a caller ends only its wait; the watch keeps going and saves the outcome.
    @Test
    func `Cancelling a caller doesn't stop the watch`() async throws {
        let gate = Suspension()
        let sending = try Self.sending(statusGate: gate)
        let record = try await sending.send()
        await gate.waitUntilStarted()
        let caller = Task { try await sending.store.watch(record.id, for: sending.key) }

        caller.cancel()
        await #expect(throws: CancellationError.self) { try await caller.value }
        gate.resume()

        #expect(try await sending.settle(record) == .succeeded)
        #expect(await sending.records.value?.first?.status == .succeeded)
    }

    /// A record that isn't kept can't be watched.
    @Test
    func `Watching a record that isn't kept throws`() async throws {
        let sending = try Self.sending()

        await #expect(throws: TransactionStoreError.missingRecord) {
            try await sending.store.watch("unknown", for: sending.key)
        }
    }

    /// Erasing stops every watch and forgets every record.
    @Test
    func `Erasing stops the watches and forgets the records`() async throws {
        // The watch never settles: no status exists and the blockhash stays valid.
        let sending = try Self.sending(statuses: [.status(nil)])
        let record = try await sending.send()
        for await _ in sending.sockets.openings { break }

        try await sending.store.erase()

        await sending.sockets.waitUntilClosed()
        #expect(sending.store.records(for: sending.key).isEmpty)
        #expect(await sending.records.value == nil)
        await #expect(throws: TransactionStoreError.missingRecord) {
            try await sending.store.watch(record.id, for: sending.key)
        }
    }

    // MARK: Reading

    /// Recent payments list the latest succeeded payment to each recipient across several accounts, the latest to
    /// land first, without moves, unsettled or failed payments, or other recipients beyond the limit.
    @Test
    func `Recent payments list each recipient's latest succeeded payment`() async throws {
        let (first, second) = (UUID(), UUID())
        let (bruno, carla, dana) = try (Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"),
                                        Address("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"),
                                        Address("8CW93AFYFKj2rKZRq3YjLesb4XbgtAiq8k2FgfruVZL5"))
        let storages = try [
            TransactionRecord.Key(account: first, network: .devnet): StoredValue<[TransactionRecord]>([
                .fixture(Self.payment(to: bruno), signature: "bruno-old", account: first, status: .succeeded,
                         settled: 10),
                .fixture(Self.payment(to: carla), signature: "carla", account: first, status: .succeeded, settled: 30),
                .fixture(Self.payment(to: dana), signature: "dana-failed", account: first, status: .failed,
                         settled: 60),
                .fixture(.privateDeposit(lamports: 1), signature: "deposit", account: first, status: .succeeded,
                         settled: 70),
            ]),
            TransactionRecord.Key(account: second, network: .devnet): StoredValue<[TransactionRecord]>([
                .fixture(Self.payment(to: bruno), signature: "bruno-new", account: second, status: .succeeded,
                         settled: 40),
                .fixture(Self.payment(to: dana), signature: "dana-pending", account: second),
                .fixture(Self.payment(to: dana), signature: "dana", account: second, status: .succeeded, settled: 20),
            ]),
        ]
        let store = TransactionStore(storage: { storages[$0] ?? StoredValue() }) { _ in
            throw SubmitterError.noProviders
        }
        let keys = Array(storages.keys)
        for key in keys { await store.load(key) }

        #expect(store.recentPayments(for: keys, limit: 10).map(\.id) == ["bruno-new", "carla", "dana"])
        #expect(store.recentPayments(for: keys, limit: 2).map(\.id) == ["bruno-new", "carla"])
    }

    /// A key's records read once, on first load, and show what's saved.
    @Test
    func `Loading reads a key's saved records`() async throws {
        let account = UUID()
        let key = TransactionRecord.Key(account: account, network: .devnet)
        let saved = StoredValue([TransactionRecord.fixture(try Self.payment(), signature: "saved", account: account)])
        let store = TransactionStore.inMemory(saved) { _ in throw SubmitterError.noProviders }
        #expect(store.phase(for: key) == .unloaded)

        await store.load(key)
        await store.load(key)

        #expect(store.phase(for: key) == .loaded)
        #expect(store.records(for: key).map(\.id) == ["saved"])
        #expect(await saved.loads == 1)
    }

    /// Each account's records on each network are kept in their own file, at `<network>/<account>.json`.
    @Test
    func `Each key's records are kept in their own file`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = UUID()
        let record = TransactionRecord.fixture(try Self.payment(), signature: "saved", account: account)

        try await TransactionStore.files(in: directory)(record.key).save([record])

        let file = directory.appending(path: "devnet/\(account.uuidString).json")
        #expect(try JSONDecoder().decode([TransactionRecord].self, from: Data(contentsOf: file)) == [record])
    }

    // MARK: Coordinators

    /// No coordinator exists until something needs one; each network's coordinator is then created once.
    @Test
    func `Each network's coordinator is created on first use and then reused`() throws {
        var made: [Network] = []
        let store = TransactionStore.inMemory { network in
            made.append(network)
            return try TransactionCoordinator.unused(on: network)
        }
        #expect(made.isEmpty)

        _ = try store.coordinator(for: .devnet)
        _ = try store.coordinator(for: .devnet)
        _ = try store.coordinator(for: .mainnet)

        #expect(made == [.devnet, .mainnet])
    }

    /// A coordinator that couldn't be created isn't kept, so the next request creates it.
    @Test
    func `A failed creation is tried again on the next request`() throws {
        var attempts = 0
        let store = TransactionStore.inMemory { network in
            attempts += 1
            // The first attempt has no route that sends on the network.
            return try TransactionCoordinator.unused(on: network, routes: attempts == 1 ? [] : nil)
        }

        #expect(throws: SubmitterError.noProviders) { _ = try store.coordinator(for: .devnet) }
        _ = try store.coordinator(for: .devnet)

        #expect(attempts == 2)
    }

    // MARK: Fixtures

    /// Checks that nothing was recorded or sent.
    /// - Parameter sending: The store and what stands behind it.
    private static func expectNothingSent(by sending: Sending) async {
        #expect(await sending.records.value == nil)
        #expect(sending.store.records(for: sending.key).isEmpty)
        #expect(await sending.sent.requests.isEmpty)
    }

    /// Creates a store whose devnet coordinator answers from local responses and sockets.
    /// - Parameters:
    ///   - recovery: The recovery storage that signing reads, or `nil` for the fixture recovery.
    ///   - statuses: The watch's status reads, in arrival order.
    ///   - height: The finalized block height of the watch's epoch reads.
    ///   - statusGate: An optional suspension of the watch's status reads.
    ///   - sockets: The watch's connections.
    ///   - sent: The responses that acknowledge each sent transaction.
    ///   - fixture: The account and transaction to send, or `nil` for a new fixture.
    ///   - records: The in-memory records.
    /// - Returns: The store and what stands behind it.
    /// - Throws: A fixture error.
    private static func sending(recovery: SigningRecoveryStore? = nil,
                                statuses: [GetSignatureStatuses.Response] = [.status(.finalized)],
                                height: UInt64 = 500, statusGate: Suspension? = nil,
                                sockets: SocketSequence = SocketSequence(), sent: HTTPResponses = .sending(),
                                fixture: SigningFixture? = nil,
                                records: StoredValue<[TransactionRecord]> = StoredValue()) throws -> Sending {
        let fixture = try fixture ?? SigningFixture()
        let coordinator = try LocalTransactions(fixture: fixture, recovery: recovery, statuses: statuses, height: height,
                                                statusGate: statusGate, sockets: sockets, sent: sent).coordinator
        return Sending(store: .inMemory(records) { _ in coordinator }, records: records, account: fixture.account,
                       recipient: fixture.transfer.accounts[1].address, sent: sent, sockets: sockets)
    }

    /// A 1-lamport SOL payment.
    /// - Parameter recipient: The recipient, or `nil` for a fixed address.
    /// - Returns: The payment.
    /// - Throws: A fixture error.
    private static func payment(to recipient: Address? = nil) throws -> TransactionRecord.Kind {
        .payment(recipient: try recipient ?? Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"), mint: nil,
                 units: 1)
    }
}

/// Records each settling with the saved status and the settled count at that moment.
private actor RecordingSettling: TransactionSettling {
    /// One settling.
    struct Call: Equatable {
        /// The settled transaction's signature.
        let signature: String
        /// The transaction's saved status when the settling ran.
        let saved: TransactionRecord.Status?
        /// The store's settled count when the settling ran.
        let settledCount: Int
    }

    private let records: StoredValue<[TransactionRecord]>
    private let store: TransactionStore
    private let key: TransactionRecord.Key
    private(set) var calls: [Call] = []

    /// Reads the saved records and the store's settled count at each settling.
    /// - Parameters:
    ///   - records: The store's in-memory records.
    ///   - store: The store, whose settled count is read.
    ///   - key: The account and network whose settled count is read.
    init(records: StoredValue<[TransactionRecord]>, store: TransactionStore, key: TransactionRecord.Key) {
        self.records = records
        self.store = store
        self.key = key
    }

    /// Records the settling.
    /// - Parameter confirmation: The settled outcome.
    func settle(_ confirmation: widgets.Confirmation) async {
        let signature = confirmation.submission.signature
        let saved = await records.value?.first { $0.id == signature }?.status
        calls.append(Call(signature: signature, saved: saved, settledCount: await store.settledCount(for: key)))
    }
}
