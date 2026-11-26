import Foundation
import Storage
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionStoreTests {
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    @Test
    func `A sent payment is saved as pending`() async throws {
        let gate = Suspension()
        let sending = try LocalSending(statusGate: gate)
        let simulation = try await sending.simulate()

        let record = try await sending.send(simulation)

        #expect(record.isPending)
        #expect(record.settled == nil)
        #expect(record.kind == .payment)
        #expect(record.key == sending.key)
        #expect(record.transaction == simulation.transaction)
        #expect(record.outcome.lastValidBlockHeight == 550)
        let saved = await sending.pending.value
        #expect(saved == [record])
        gate.resume()
        #expect(try await sending.settle(record) == .succeeded(slot: 405))
    }

    @Test
    func `Payments sent with a shared authentication read recovery through it`() async throws {
        let recovery = SigningRecoveryStore(recovery: try SigningFixture().recovery)
        let sending = try LocalSending(recovery: recovery)
        let (store, account) = (sending.store, sending.account)
        let simulations = [try await sending.simulate(), try await sending.simulate()]

        let records = try await store.coordinator(for: .devnet).withSharedAuthentication { shared in
            var records: [TransactionRecord] = []
            for simulation in simulations {
                records.append(try await store.send(simulation, as: .payment, from: account, using: shared))
            }
            return records
        }

        let shared = await recovery.shared
        #expect(records.count == 2)
        #expect(shared.map(\.reason) == ["Approve transaction"])
        #expect(await shared.first?.store.reads.count == 2)
        #expect(await recovery.reads.isEmpty)
    }

    @Test(arguments: [CancellationError(), CocoaError(.fileReadUnknown)] as [any Error])
    func `A payment that isn't signed records nothing`(_ error: any Error) async throws {
        let sending = try LocalSending(recovery: SigningRecoveryStore(recovery: try SigningFixture().recovery,
                                                                      error: error))

        let thrown = try await #require(throws: (any Error).self) { try await sending.send() }

        #expect(thrown as NSError == error as NSError)
        await Self.expectNothingSent(by: sending)
    }

    @Test(arguments: [(true, false), (false, true)])
    func `A payment is sent and settles when its saved records can't be read or written`(
        failsLoading: Bool, failsSaving: Bool
    ) async throws {
        let sending = try LocalSending(pending: StoredValue(failsLoading: failsLoading, failsSaving: failsSaving))

        let record = try await sending.send()

        #expect(try await sending.settle(record) == .succeeded(slot: 405))
        #expect(sending.store.record(record.id, for: sending.key)?.outcome.status == .succeeded(slot: 405))
    }

    @Test
    func `A payment with unknown delivery is recorded and watched`() async throws {
        let gate = Suspension()
        let sending = try LocalSending(statusGate: gate, sent: HTTPResponses([:], error: Self.rateLimit))

        let record = try await sending.send()

        #expect(record.isPending)
        let saved = await sending.pending.value
        #expect(saved == [record])
        gate.resume()
        #expect(try await sending.settle(record) == .succeeded(slot: 405))
    }

    @Test
    func `Cancelling the caller doesn't stop delivery`() async throws {
        let (delivery, status) = (Suspension(), Suspension())
        let sending = try LocalSending(statusGate: status, sent: .sending(gate: delivery))
        let simulation = try await sending.simulate()
        let caller = Task { try await sending.send(simulation) }
        await delivery.waitUntilStarted()

        caller.cancel()
        delivery.resume()
        let record = try await caller.value

        #expect(await !sending.sent.wasCancelled)
        let saved = await sending.pending.value
        #expect(saved == [record])
        status.resume()
        #expect(try await sending.settle(record) == .succeeded(slot: 405))
    }

    @Test(arguments: [
        (GetSignatureStatuses.Response.status(.finalized), UInt64(500), TransactionOutcome.Status.succeeded(slot: 405)),
        (.status(.finalized, error: .instructionError(0, custom: 6001)), 500,
         .failed(slot: 405, .program(instruction: 0, code: 6001))),
        (.status(nil), 600, .dropped),
    ])
    func `A settled record keeps its outcome and is no longer saved`(
        status: GetSignatureStatuses.Response, height: UInt64, expected: TransactionOutcome.Status
    ) async throws {
        let sending = try LocalSending(statuses: [status], height: height)
        let record = try await sending.send()

        let settled = try await sending.settle(record)

        #expect(settled == expected)
        let kept = try #require(sending.store.record(record.id, for: sending.key))
        #expect(kept.outcome.status == expected)
        #expect(kept.settled != nil)
        #expect(await sending.pending.value == [])
    }

    @Test
    func `The settling runs once after the outcome is kept`() async throws {
        let sending = try LocalSending()
        let settling = RecordingSettling(pending: sending.pending, store: sending.store, key: sending.key)
        let record = try await sending.send(settling: settling)

        _ = try await sending.settle(record)
        #expect(try await sending.settle(record) == .succeeded(slot: 405))

        let expected = RecordingSettling.Call(status: .succeeded(slot: 405), isKept: true, saved: [], settledCount: 0)
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

        await #expect(throws: refusal) { try await sending.store.watch(record.id, for: sending.key) }
        let saved = await sending.pending.value
        #expect(saved == [record])
        #expect(sending.store.settledCount(for: sending.key) == 0)

        #expect(try await sending.settle(record) == .succeeded(slot: 405))
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

        #expect(try await sending.settle(record) == .succeeded(slot: 405))
        #expect(sending.store.record(record.id, for: sending.key)?.outcome.status == .succeeded(slot: 405))
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
        #expect(await sending.pending.value == nil)
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
        #expect(await sending.pending.value == [])
        await #expect(throws: TransactionStoreError.missingRecord) {
            try await sending.store.watch(record.id, for: sending.key)
        }
    }

    @Test
    func `Erasing an account forgets its records on every network only`() async throws {
        let (erased, other) = (UUID(), UUID())
        let kept = TransactionRecord.fixture(.payment, signature: "kept", account: other)
        let pending = StoredValue([.fixture(.payment, signature: "mainnet", account: erased, network: .mainnet),
                                   .fixture(.payment, signature: "devnet", account: erased), kept])
        let store = TransactionStore.inMemory(pending)

        try await store.erase(account: erased)

        #expect(await pending.value == [kept])
        #expect(store.records(for: kept.key) == [kept])
        for network in Network.allCases {
            #expect(store.records(for: TransactionRecord.Key(account: erased, network: network)).isEmpty)
        }
    }

    @Test
    func `Loading reads the saved pending records once`() async throws {
        let record = TransactionRecord.fixture(.payment, signature: "saved", account: UUID())
        let saved = StoredValue([record])
        let store = TransactionStore.inMemory(saved)
        #expect(store.records(for: record.key).isEmpty)

        await store.load()
        await store.load()

        #expect(store.records(for: record.key) == [record])
        #expect(await saved.loads == 1)
    }

    @Test
    func `Pending records are kept in their file as version 1, replacing a file that can't be used`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = TransactionRecord.fixture(.payment, signature: "saved", account: UUID())
        let file = directory.appending(path: "pending.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"[{"kind": "payment", "amount": 1000000, "signature": "old"}]"#.utf8).write(to: file)
        let storage = TransactionStore.file(in: directory)

        #expect(try await storage.load() == [])
        try await storage.save([record])

        let coding = VersionedJSONCoding<[TransactionRecord]>(version: 1, unusable: .unreadable)
        #expect(try coding.decode(Data(contentsOf: file)) == [record])
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
            if attempts == 1 { throw TransactionCoordinatorError.unsupportedNetwork }
            return try TransactionCoordinator.unused(on: network)
        }

        #expect(throws: TransactionCoordinatorError.unsupportedNetwork) { _ = try store.coordinator(for: .devnet) }
        _ = try store.coordinator(for: .devnet)

        #expect(attempts == 2)
    }

    private static func expectNothingSent(by sending: LocalSending) async {
        #expect(await sending.pending.value == nil)
        #expect(sending.store.records(for: sending.key).isEmpty)
        #expect(await sending.sent.requests.isEmpty)
    }
}

private actor RecordingSettling: TransactionSettling {
    struct Call: Equatable {
        let status: TransactionOutcome.Status
        let isKept: Bool
        let saved: [TransactionRecord]?
        let settledCount: Int
    }

    private let pending: StoredValue<[TransactionRecord]>
    private let store: TransactionStore
    private let key: TransactionRecord.Key
    private(set) var calls: [Call] = []

    init(pending: StoredValue<[TransactionRecord]>, store: TransactionStore, key: TransactionRecord.Key) {
        self.pending = pending
        self.store = store
        self.key = key
    }

    func settle(_ outcome: TransactionOutcome) async {
        let isKept = await store.record(outcome.signature, for: key)?.outcome == outcome
        calls.append(Call(status: outcome.status, isKept: isKept, saved: await pending.value,
                          settledCount: await store.settledCount(for: key)))
    }
}
