import Foundation
@testable import RPC
import Storage
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionStoreTests {
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    @Test
    func `A sent payment is saved as pending`() async throws {
        let sending = try LocalSending()

        let record = try await sending.send()

        #expect(record.status == .pending)
        #expect(record.settled == nil)
        #expect(record.kind == sending.payment)
        #expect(record.key == sending.key)
        #expect(record.lastValidBlockHeight == 550)
        #expect(await sending.savedOnly(record))
        #expect(try await sending.settle(record) == .succeeded)
    }

    @Test
    func `A cancelled authentication records nothing`() async throws {
        let sending = try LocalSending(recovery: SigningRecoveryStore(recovery: try SigningFixture().recovery,
                                                                      error: CancellationError()))

        await #expect(throws: CancellationError.self) { try await sending.send() }

        await Self.expectNothingSent(by: sending)
    }

    @Test
    func `A payment that can't be signed records nothing`() async throws {
        let sending = try LocalSending(recovery: SigningRecoveryStore(recovery: try SigningFixture().recovery,
                                                                      error: CocoaError(.fileReadUnknown)))

        await #expect(throws: CocoaError(.fileReadUnknown)) { try await sending.send() }

        await Self.expectNothingSent(by: sending)
    }

    @Test
    func `A payment with unknown delivery is recorded and watched`() async throws {
        let sending = try LocalSending(sent: HTTPResponses([:], error: Self.rateLimit))

        let record = try await sending.send()

        #expect(record.status == .pending)
        #expect(await sending.savedOnly(record))
        #expect(try await sending.settle(record) == .succeeded)
    }

    @Test
    func `Cancelling the caller doesn't stop delivery`() async throws {
        let gate = Suspension()
        let sending = try LocalSending(sent: .sending(gate: gate))
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

    @Test
    func `Only the latest 200 records are kept`() async throws {
        let fixture = try SigningFixture()
        let saved = try (0..<200).map {
            try TransactionRecord.fixture(LocalSending.payment(), signature: "saved-\($0)", account: fixture.account.id)
        }
        let sending = try LocalSending(fixture: fixture, records: StoredValue(saved))

        let record = try await sending.send()

        let kept = try #require(await sending.records.value)
        #expect(kept.count == 200)
        #expect(kept.first?.id == record.id)
        #expect(kept.last?.id == "saved-198")
        #expect(sending.store.records(for: sending.key).map(\.id) == kept.map(\.id))
        _ = try await sending.settle(record)
    }

    @Test(arguments: [
        (GetSignatureStatuses.Response.status(.finalized), UInt64(500), TransactionRecord.Status.succeeded),
        (.status(.finalized, error: TransactionError(name: "InstructionError", details: nil)), 500, .failed),
        (.status(nil), 600, .dropped),
    ])
    func `A settled watch saves its outcome`(status: GetSignatureStatuses.Response, height: UInt64,
                                             expected: TransactionRecord.Status) async throws {
        let sending = try LocalSending(statuses: [status], height: height)
        let record = try await sending.send()

        let settled = try await sending.settle(record)

        #expect(settled == expected)
        let saved = try #require(await sending.records.value?.first)
        #expect(saved.status == expected)
        #expect(try #require(saved.settled) >= saved.created)
        #expect(sending.store.record(record.id, for: sending.key) == saved)
    }

    @Test
    func `The settling runs once after the outcome is saved`() async throws {
        let sending = try LocalSending()
        let settling = RecordingSettling(records: sending.records, store: sending.store, key: sending.key)
        let record = try await sending.send(settling: settling)

        _ = try await sending.settle(record)
        _ = try await sending.settle(record)

        let expected = RecordingSettling.Call(signature: record.id, saved: .succeeded, settledCount: 0)
        #expect(await settling.calls == [expected])
        #expect(sending.store.settledCount(for: sending.key) == 1)
    }

    @Test
    func `A stopped watch reports its error once and can watch again`() async throws {
        let refusal = Self.rateLimit
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let sending = try LocalSending(sockets: sockets)
        let record = try await sending.send()
        for await _ in sockets.openings { break }

        await #expect(throws: DeliveryError.self) { try await sending.store.watch(record.id, for: sending.key) }
        #expect(await sending.records.value?.first?.status == .pending)
        #expect(sending.store.settledCount(for: sending.key) == 0)

        #expect(try await sending.settle(record) == .succeeded)
        #expect(sockets.sockets.count == 2)
    }

    @Test
    func `Cancelling a caller doesn't stop the watch`() async throws {
        let gate = Suspension()
        let sending = try LocalSending(statusGate: gate)
        let record = try await sending.send()
        await gate.waitUntilStarted()
        let caller = Task { try await sending.store.watch(record.id, for: sending.key) }

        caller.cancel()
        await #expect(throws: CancellationError.self) { try await caller.value }
        gate.resume()

        #expect(try await sending.settle(record) == .succeeded)
        #expect(await sending.records.value?.first?.status == .succeeded)
    }

    @Test
    func `Watching a record that isn't kept throws`() async throws {
        let sending = try LocalSending()

        await #expect(throws: TransactionStoreError.missingRecord) {
            try await sending.store.watch("unknown", for: sending.key)
        }
    }

    @Test
    func `Erasing stops the watches and forgets the records`() async throws {
        let sending = try LocalSending(statuses: [.status(nil)])
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

    @Test
    func `Erasing an account stops its watches and forgets its records`() async throws {
        let sending = try LocalSending(statuses: [.status(nil)])
        let record = try await sending.send()
        for await _ in sending.sockets.openings { break }

        try await sending.store.erase(account: sending.account.id)

        await sending.sockets.waitUntilClosed()
        #expect(sending.store.records(for: sending.key).isEmpty)
        #expect(await sending.records.value == nil)
        await #expect(throws: TransactionStoreError.missingRecord) {
            try await sending.store.watch(record.id, for: sending.key)
        }
    }

    @Test
    func `Erasing an account deletes its records on every network only`() async throws {
        let fixture = try SigningFixture()
        let other = UUID()
        let mainnet = StoredValue([try TransactionRecord.fixture(LocalSending.payment(), signature: "mainnet",
                                                                 account: fixture.account.id, network: .mainnet)])
        let devnet = StoredValue([try TransactionRecord.fixture(LocalSending.payment(), signature: "devnet",
                                                                account: fixture.account.id)])
        let kept = StoredValue([try TransactionRecord.fixture(LocalSending.payment(), signature: "kept",
                                                              account: other)])
        let otherKey = TransactionRecord.Key(account: other, network: .devnet)
        let sending = try LocalSending(fixture: fixture, records: devnet, otherRecords: [
            TransactionRecord.Key(account: fixture.account.id, network: .mainnet): mainnet, otherKey: kept,
        ])
        await sending.store.load(sending.key)
        await sending.store.load(otherKey)

        try await sending.store.erase(account: fixture.account.id)

        #expect(await mainnet.value == nil)
        #expect(await devnet.value == nil)
        #expect(await kept.value?.map(\.id) == ["kept"])
        #expect(sending.store.records(for: otherKey).map(\.id) == ["kept"])
    }

    @Test
    func `Recent payments list each recipient's latest succeeded payment`() async throws {
        let (first, second) = (UUID(), UUID())
        let (bruno, carla, dana) = try (Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"),
                                        Address("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"),
                                        Address("8CW93AFYFKj2rKZRq3YjLesb4XbgtAiq8k2FgfruVZL5"))
        let storages = try [
            TransactionRecord.Key(account: first, network: .devnet): StoredValue<[TransactionRecord]>([
                .fixture(LocalSending.payment(to: bruno), signature: "bruno-old", account: first, status: .succeeded,
                         settled: 10),
                .fixture(LocalSending.payment(to: carla), signature: "carla", account: first, status: .succeeded,
                         settled: 30),
                .fixture(LocalSending.payment(to: dana), signature: "dana-failed", account: first, status: .failed,
                         settled: 60),
                .fixture(.privateDeposit(lamports: 1), signature: "deposit", account: first, status: .succeeded,
                         settled: 70),
            ]),
            TransactionRecord.Key(account: second, network: .devnet): StoredValue<[TransactionRecord]>([
                .fixture(LocalSending.payment(to: bruno), signature: "bruno-new", account: second, status: .succeeded,
                         settled: 40),
                .fixture(LocalSending.payment(to: dana), signature: "dana-pending", account: second),
                .fixture(LocalSending.payment(to: dana), signature: "dana", account: second, status: .succeeded,
                         settled: 20),
            ]),
        ]
        let store = TransactionStore.inMemory(storages)
        let keys = Array(storages.keys)
        for key in keys { await store.load(key) }

        #expect(store.recentPayments(for: keys, limit: 10).map(\.id) == ["bruno-new", "carla", "dana"])
        #expect(store.recentPayments(for: keys, limit: 2).map(\.id) == ["bruno-new", "carla"])
    }

    @Test
    func `Loading reads a key's saved records`() async throws {
        let account = UUID()
        let key = TransactionRecord.Key(account: account, network: .devnet)
        let saved = StoredValue([TransactionRecord.fixture(try LocalSending.payment(), signature: "saved",
                                                           account: account)])
        let store = TransactionStore.inMemory(saved) { _ in throw SubmitterError.noProviders }
        #expect(store.phase(for: key) == .unloaded)

        await store.load(key)
        await store.load(key)

        #expect(store.phase(for: key) == .loaded)
        #expect(store.records(for: key).map(\.id) == ["saved"])
        #expect(await saved.loads == 1)
    }

    @Test
    func `Each key's records are kept in their own file`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = UUID()
        let record = TransactionRecord.fixture(try LocalSending.payment(), signature: "saved", account: account)

        try await TransactionStore.files(in: directory)(record.key).save([record])

        let file = directory.appending(path: "devnet/\(account.uuidString).json")
        #expect(try JSONDecoder().decode([TransactionRecord].self, from: Data(contentsOf: file)) == [record])
    }

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

    @Test
    func `A failed creation is tried again on the next request`() throws {
        var attempts = 0
        let store = TransactionStore.inMemory { network in
            attempts += 1
            return try TransactionCoordinator.unused(on: network, routes: attempts == 1 ? [] : nil)
        }

        #expect(throws: SubmitterError.noProviders) { _ = try store.coordinator(for: .devnet) }
        _ = try store.coordinator(for: .devnet)

        #expect(attempts == 2)
    }

    private static func expectNothingSent(by sending: LocalSending) async {
        #expect(await sending.records.value == nil)
        #expect(sending.store.records(for: sending.key).isEmpty)
        #expect(await sending.sent.requests.isEmpty)
    }
}

private actor RecordingSettling: TransactionSettling {
    struct Call: Equatable {
        let signature: String
        let saved: TransactionRecord.Status?
        let settledCount: Int
    }

    private let records: StoredValue<[TransactionRecord]>
    private let store: TransactionStore
    private let key: TransactionRecord.Key
    private(set) var calls: [Call] = []

    init(records: StoredValue<[TransactionRecord]>, store: TransactionStore, key: TransactionRecord.Key) {
        self.records = records
        self.store = store
        self.key = key
    }

    func settle(_ confirmation: widgets.Confirmation) async {
        let signature = confirmation.submission.signature
        let saved = await records.value?.first { $0.id == signature }?.status
        calls.append(Call(signature: signature, saved: saved, settledCount: await store.settledCount(for: key)))
    }
}
