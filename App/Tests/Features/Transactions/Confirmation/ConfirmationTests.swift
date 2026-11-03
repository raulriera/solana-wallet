import Foundation
import RPC
import Synchronization
import Testing
@testable import widgets

struct ConfirmationTests {
    private static let instructionError = TransactionError(name: "InstructionError",
                                                           details: .array([.integer(1), .object(["Custom": .integer(6001)])]))
    private static let unavailable = RPCError.http(statusCode: 503, retryAfter: nil)
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")
    private static let rejectedKey = RPCError.http(statusCode: 401, retryAfter: nil)
    private static let finalizedStatus = GetSignatureStatuses.Status(slot: 405, confirmations: nil, error: nil,
                                                                     confirmationStatus: .finalized)

    private let submission = Submission(signature: ExternalFixture.signature, network: .devnet, lastValidBlockHeight: 650)

    @Test(.timeLimit(.minutes(1)), arguments: [
        ("null", widgets.Confirmation.Outcome.succeeded),
        (#"{"InstructionError":[1,{"Custom":6001}]}"#, .failed(Self.instructionError)),
    ])
    func `A landing settles the watch with its execution result`(error: String, outcome: widgets.Confirmation.Outcome) async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil)], epochs: [epoch(slot: 1_000, height: 600)])
        let sockets = SocketSequence { _ in SocketSequence.watch(then: [SocketFixture.landingNotification(error: error)]) }

        let confirmation = try await confirmer(http, sockets).confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: nil, outcome: outcome))
        let requests = await http.requests
        try #require(requests.count == 2)
        let statusRead = try #require(requests.first { try $0.rpcMethod == "getSignatureStatuses" })
        let epochRead = try #require(requests.first { try $0.rpcMethod == "getEpochInfo" })
        #expect(try statusRead.rpcParameters[0] as? [String] == [submission.signature])
        #expect(try (statusRead.rpcParameters[1] as? [String: Bool])?["searchTransactionHistory"] == true)
        #expect(try (epochRead.rpcParameters[0] as? [String: Any])?["commitment"] as? String == "finalized")
        #expect(sockets.sockets.count == 1)
        await sockets.waitUntilClosed()
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        (TransactionError?.none, widgets.Confirmation.Outcome.succeeded),
        (Self.instructionError, .failed(Self.instructionError)),
    ])
    func `A catch-up read settles a transaction that landed before the subscription`(
        error: TransactionError?, outcome: widgets.Confirmation.Outcome
    ) async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(status(.finalized, error: error))],
                                                  epochs: [epoch(slot: 1_000, height: 600)])
        let sockets = SocketSequence()

        let confirmation = try await confirmer(http, sockets).confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: 405, outcome: outcome))
        #expect(try await reads(of: http)["getSignatureStatuses"] == 1)
        #expect(sockets.sockets.count == 1)
        await sockets.waitUntilClosed()
    }

    @Test(.timeLimit(.minutes(1)), arguments: [Commitment.processed, .confirmed, nil])
    func `A status that isn't finalized keeps watching until the landing`(_ commitment: Commitment?) async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(status(commitment))],
                                                  epochs: [epoch(slot: 1_000, height: 600)])
        let sockets = SocketSequence { _ in
            SocketSequence.watch(then: [SocketFixture.rootNotification(1_010), SocketFixture.landingNotification()])
        }

        let confirmation = try await confirmer(http, sockets).confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: nil, outcome: .succeeded))
        #expect(try await reads(of: http) == ["getSignatureStatuses": 1, "getEpochInfo": 1])
    }

    @Test(.timeLimit(.minutes(1)))
    func `Roots check the expiry only from the scheduled slot, then a missing status reports a drop`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(nil, at: 1_062)], epochs: [
            epoch(slot: 1_000, height: 600), epoch(slot: 1_051, height: 640), epoch(slot: 1_062, height: 651),
        ])

        let (confirmation, reads) = try await confirm(over: http, pacing: [1_010, 1_050, 1_051, 1_061, 1_062])

        #expect(confirmation == Confirmation(submission: submission, slot: nil, outcome: .dropped))
        #expect(reads == [2, 2, 2, 3, 3])
        #expect(try await self.reads(of: http) == ["getSignatureStatuses": 2, "getEpochInfo": 3])
    }

    @Test(.timeLimit(.minutes(1)))
    func `A root ahead of the finalized slot causes no extra reads`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil)], epochs: [
            epoch(slot: 1_000, height: 600), epoch(slot: 1_060, height: 610),
        ])
        let sockets = SocketSequence { _ in
            SocketSequence.watch(then: [1_100, 1_101, 1_140].map { SocketFixture.rootNotification($0) }
                                 + [SocketFixture.landingNotification()])
        }

        let confirmation = try await confirmer(http, sockets).confirm(submission)

        #expect(confirmation.outcome == .succeeded)
        #expect(try await reads(of: http) == ["getSignatureStatuses": 1, "getEpochInfo": 2])
    }

    @Test(.timeLimit(.minutes(1)))
    func `A status found after expiry settles the watch with its outcome`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(status(.finalized, error: Self.instructionError))],
                                                  epochs: [epoch(slot: 1_000, height: 600), epoch(slot: 1_051, height: 651)])
        let sockets = SocketSequence { _ in SocketSequence.watch(then: [SocketFixture.rootNotification(1_051)]) }

        let confirmation = try await confirmer(http, sockets).confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: 405, outcome: .failed(Self.instructionError)))
        #expect(try await reads(of: http) == ["getSignatureStatuses": 2, "getEpochInfo": 2])
    }

    @Test(.timeLimit(.minutes(1)))
    func `A status read behind the expiry slot waits for roots to cover the lag`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(nil, at: 1_041), response(nil, at: 1_051)],
                                                  epochs: [epoch(slot: 1_000, height: 600), epoch(slot: 1_051, height: 651)])

        let (confirmation, reads) = try await confirm(over: http, pacing: [1_051, 1_060, 1_061])

        #expect(confirmation == Confirmation(submission: submission, slot: nil, outcome: .dropped))
        #expect(reads == [2, 4, 4])
        #expect(try await self.reads(of: http) == ["getSignatureStatuses": 3, "getEpochInfo": 2])
    }

    @Test(.timeLimit(.minutes(1)))
    func `A processed status after expiry is read again, then a missing one reports a drop`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(status(.processed), at: 1_051), response(nil)],
                                                  epochs: [epoch(slot: 1_000, height: 600), epoch(slot: 1_051, height: 651)])

        let (confirmation, reads) = try await confirm(over: http, pacing: [1_051, 1_052])

        #expect(confirmation == Confirmation(submission: submission, slot: nil, outcome: .dropped))
        #expect(reads == [2, 4])
        #expect(try await self.reads(of: http) == ["getSignatureStatuses": 3, "getEpochInfo": 2])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        (UInt64.max, UInt64(1_000), UInt64(0), ["getSignatureStatuses": 1, "getEpochInfo": 1]),
        (650, .max, 651, ["getSignatureStatuses": 2, "getEpochInfo": 1]),
    ])
    func `Checks due past the largest slot keep watching until the landing`(
        lastValidBlockHeight: UInt64, slot: UInt64, height: UInt64, methods: [String: Int]
    ) async throws {
        let receipt = Submission(signature: submission.signature, network: .devnet, lastValidBlockHeight: lastValidBlockHeight)
        let http = try HTTPResponses.confirmation(statuses: [response(nil)], epochs: [epoch(slot: slot, height: height)])
        let sockets = SocketSequence { _ in
            SocketSequence.watch(then: [SocketFixture.rootNotification(1_010), SocketFixture.landingNotification()])
        }

        let confirmation = try await confirmer(http, sockets).confirm(receipt)

        #expect(confirmation == Confirmation(submission: receipt, slot: nil, outcome: .succeeded))
        #expect(try await reads(of: http) == methods)
        await sockets.waitUntilClosed()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A catch-up read past an expiry found alongside it proves a drop`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil, at: 1_060)],
                                                  epochs: [epoch(slot: 1_051, height: 651)])
        let sockets = SocketSequence()

        let confirmation = try await confirmer(http, sockets).confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: nil, outcome: .dropped))
        #expect(try await reads(of: http) == ["getSignatureStatuses": 1, "getEpochInfo": 1])
        await sockets.waitUntilClosed()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A reconnection after expiry settles the watch with one status read`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil, at: 1_000), response(nil, at: 1_041),
                                                             response(nil, at: 1_051)],
                                                  epochs: [epoch(slot: 1_051, height: 651)])
        let sockets = SocketSequence { connection in
            guard connection == 0 else { return SocketSequence.watch() }
            return SocketSequence.watch(then: [1_052, 1_060].map { SocketFixture.rootNotification($0) }
                                        + [SocketFixture.serverError(code: -32005)])
        }
        let waits = Mutex<[Duration]>([])

        let confirmation = try await confirmer(http, sockets, clock: clock(wait: { duration in
            waits.withLock { $0.append(duration) }
        })).confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: nil, outcome: .dropped))
        #expect(waits.withLock(\.self) == [.seconds(2)])
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
        #expect(try await reads(of: http) == ["getSignatureStatuses": 3, "getEpochInfo": 1])
    }

    @Test(.timeLimit(.minutes(1)))
    func `A lost connection reconnects after two seconds and catches up`() async throws {
        let held = Suspension()
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(status(.finalized))],
                                                  epochs: [epoch(slot: 1_000, height: 600)], gate: held, heldMethod: "getEpochInfo")
        let sockets = SocketSequence()
        let waits = Mutex<[Duration]>([])
        let watch = confirmer(http, sockets, clock: clock(wait: { duration in waits.withLock { $0.append(duration) } }))
        let operation = Task { @concurrent in try await watch.confirm(submission) }
        defer { operation.cancel() }
        await held.waitUntilStarted()

        try #require(sockets.sockets.first).fail(URLError(.networkConnectionLost))
        held.resume()

        #expect(try await operation.value == Confirmation(submission: submission, slot: 405, outcome: .succeeded))
        #expect(waits.withLock(\.self) == [.seconds(2)])
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
        #expect(try await reads(of: http)["getSignatureStatuses"] == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Reconnection waits double up to a minute and reset after a subscription and its first reads`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(status(.finalized))],
                                                  epochs: [epoch(slot: 1_000, height: 600)])
        let sockets = SocketSequence { connection in
            switch connection {
            case 7: SocketSequence.watch(then: [SocketFixture.serverError(code: -32005)])
            case 9: SocketSequence.watch()
            default: SocketSequence.failing(with: URLError(.notConnectedToInternet))
            }
        }
        let waits = Mutex<[Duration]>([])

        let confirmation = try await confirmer(http, sockets, clock: clock(wait: { duration in
            waits.withLock { $0.append(duration) }
        })).confirm(submission)

        #expect(confirmation.outcome == .succeeded)
        #expect(waits.withLock(\.self) == [2, 4, 8, 16, 32, 60, 60, 2, 4].map { Duration.seconds($0) })
        #expect(sockets.sockets.count == 10)
        await sockets.waitUntilClosed()
        #expect(try await reads(of: http)["getSignatureStatuses"] == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func `A connection without roots for thirty seconds reconnects`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(status(.finalized))],
                                                  epochs: [epoch(slot: 1_000, height: 600)])
        let sockets = SocketSequence()
        let stalls = Mutex(0)
        let waits = Mutex<[Duration]>([])

        let confirmation = try await confirmer(http, sockets, clock: clock(stall: { _ in
            if stalls.withLock({ $0 += 1; return $0 }) > 1 { try await Task.sleep(for: .seconds(3_600)) }
        }, wait: { duration in waits.withLock { $0.append(duration) } })).confirm(submission)

        #expect(confirmation.outcome == .succeeded)
        #expect(stalls.withLock(\.self) == 1)
        #expect(waits.withLock(\.self) == [.seconds(2)])
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
        #expect(try await reads(of: http)["getSignatureStatuses"] == 2)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        (RPCError?.none, String?.none, SocketSequence.failing(with: Self.unavailable), 0),
        (nil, nil, SocketSequence.failing(with: RPCError.transport(.timedOut)), 0),
        (Self.unavailable, nil, SocketSequence.watch(), 2),
        (.transport(.timedOut), nil, SocketSequence.watch(), 2),
        (Self.unavailable, "getEpochInfo", SocketSequence.watch(), 2),
    ])
    func `A server or transport error reconnects instead of throwing`(
        readError: RPCError?, failingMethod: String?, connection: @escaping SocketFixture.Responder, statusReads: Int
    ) async throws {
        let held = Suspension()
        let http = try HTTPResponses.confirmation(statuses: [response(nil)], error: readError, failingMethod: failingMethod)
        let sockets = SocketSequence { _ in connection }
        let waits = Mutex<[Duration]>([])
        let watch = confirmer(http, sockets, clock: clock(wait: { duration in
            if waits.withLock({ $0.append(duration); return $0.count }) > 1 { await held.suspend() }
        }))
        let operation = Task { @concurrent in try await watch.confirm(submission) }
        defer { operation.cancel() }
        await held.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(waits.withLock(\.self) == [.seconds(2), .seconds(4)])
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
        #expect(try await reads(of: http)["getSignatureStatuses", default: 0] == statusReads)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        (Self.rateLimit, RPCError?.none, SocketSequence.failing(with: Self.rateLimit), 0),
        (Self.rejectedKey, nil, SocketSequence.failing(with: Self.rejectedKey), 0),
        (Self.rateLimit, Self.rateLimit, SocketSequence.watch(), 1),
        (Self.rejectedKey, Self.rejectedKey, SocketSequence.watch(), 1),
    ])
    func `A rate limit or rejected key stops the watch with the receipt`(
        refusal: RPCError, readError: RPCError?, connection: @escaping SocketFixture.Responder, statusReads: Int
    ) async throws {
        let http = try HTTPResponses.confirmation(statuses: [], error: readError)
        let sockets = SocketSequence { _ in connection }
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)

        let delivery = try await #require(throws: DeliveryError.self) {
            try await coordinator(over: http, sockets: sockets, store: store).confirm(submission)
        }

        #expect(delivery.submission == submission)
        #expect(delivery.cause as? RPCError == refusal)
        #expect(try await reads(of: http)["getSignatureStatuses", default: 0] == statusReads)
        #expect(sockets.sockets.count == 1)
        await sockets.waitUntilClosed()
        #expect(await store.reads.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Cancelling a coordinator's watch keeps the receipt`() async throws {
        let pending = Suspension()
        let http = try HTTPResponses.confirmation(statuses: [response(nil)], gate: pending)
        let sockets = SocketSequence()
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)
        let transactions = coordinator(over: http, sockets: sockets, store: store)
        let operation = Task { @concurrent in try await transactions.confirm(submission) }
        defer { operation.cancel() }
        await pending.waitUntilStarted()

        operation.cancel()

        let delivery = try await #require(throws: DeliveryError.self) { try await operation.value }
        #expect(delivery.submission == submission)
        #expect(delivery.cause is CancellationError)
        #expect(await http.wasCancelled)
        await sockets.waitUntilClosed()
        #expect(await store.reads.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func `A coordinator confirms a receipt without reading recovery or sending`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(status(.finalized))],
                                                  epochs: [epoch(slot: 1_000, height: 600)])
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)

        let confirmation = try await coordinator(over: http, sockets: SocketSequence(), store: store).confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: 405, outcome: .succeeded))
        let methods = try await reads(of: http)
        #expect(methods["getSignatureStatuses"] == 1)
        #expect(methods["sendTransaction"] == nil)
        #expect(await store.reads.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func `A refused subscription throws without reading or reconnecting`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [])
        let refusal: SocketFixture.Responder = { request, ordinal in
            guard ordinal == 2 else { return [try SocketFixture.acknowledgment(of: request, ordinal: ordinal)] }
            return [SocketFixture.serverError(code: -32601)]
        }
        let sockets = SocketSequence { _ in refusal }

        await #expect(throws: RPCError.server(code: -32601, message: "refused")) {
            try await confirmer(http, sockets).confirm(submission)
        }

        #expect(await http.requests.isEmpty)
        #expect(sockets.sockets.count == 1)
        await sockets.waitUntilClosed()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A malformed landing throws without reconnecting`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil)], epochs: [epoch(slot: 1_000, height: 600)])
        let malformed = Data(#"{"jsonrpc":"2.0","method":"signatureNotification","params":{"subscription":1,"result":{"context":{"slot":5},"value":{}}}}"#.utf8)
        let sockets = SocketSequence { _ in SocketSequence.watch(then: [malformed]) }

        await #expect(throws: RPCError.decoding) {
            try await confirmer(http, sockets).confirm(submission)
        }

        #expect(try await reads(of: http) == ["getSignatureStatuses": 1, "getEpochInfo": 1])
        #expect(sockets.sockets.count == 1)
        await sockets.waitUntilClosed()
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        ([GetSignatureStatuses.Status?](), 406),
        ([Self.finalizedStatus, nil], 406),
        ([Self.finalizedStatus], 404),
    ] as [([GetSignatureStatuses.Status?], UInt64)])
    func `Inconsistent status responses cannot confirm a transaction`(statuses: [GetSignatureStatuses.Status?],
                                                                     contextSlot: UInt64) async throws {
        let http = try HTTPResponses.confirmation(statuses: [.init(context: Context(slot: contextSlot), value: statuses)],
                                                  epochs: [epoch(slot: 1_000, height: 600)])
        let sockets = SocketSequence()

        await #expect(throws: ConfirmerError.invalidResponse) {
            try await confirmer(http, sockets).confirm(submission)
        }

        #expect(try await reads(of: http)["getSignatureStatuses"] == 1)
        #expect(sockets.sockets.count == 1)
        await sockets.waitUntilClosed()
    }

    @Test(.timeLimit(.minutes(1)))
    func `Cancelling a subscription closes its connection before any read`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [])
        let sockets = SocketSequence { _ in { _, _ in [] } }
        let watch = confirmer(http, sockets)
        let operation = Task { @concurrent in try await watch.confirm(submission) }
        defer { operation.cancel() }
        var openings = sockets.openings.makeAsyncIterator()
        _ = await openings.next()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(sockets.sockets.count == 1)
        await sockets.waitUntilClosed()
        #expect(await http.requests.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        (SocketSequence.watch(), 2), (SocketSequence.failing(with: URLError(.notConnectedToInternet)), 0),
    ])
    func `Cancelling a waiting watch stops it and closes its connection`(connection: @escaping SocketFixture.Responder,
                                                                        reads: Int) async throws {
        let pending = Suspension()
        let http = try HTTPResponses.confirmation(statuses: [response(nil)], epochs: [epoch(slot: 1_000, height: 600)])
        let sockets = SocketSequence { _ in connection }
        let watch = confirmer(http, sockets, clock: ControlledClock { _ in await pending.suspend() })
        let operation = Task { @concurrent in try await watch.confirm(submission) }
        defer { operation.cancel() }
        await pending.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(sockets.sockets.count == 1)
        await sockets.waitUntilClosed()
        #expect(await http.requests.count == reads)
        #expect(await !http.wasCancelled)
    }

    private func confirmer(_ http: HTTPResponses, _ sockets: SocketSequence, clock: ControlledClock? = nil) -> Confirmer {
        Confirmer(rpc: http.client(socket: { sockets.connect($0) }), clock: clock ?? self.clock())
    }

    private func confirm(over http: HTTPResponses,
                         pacing roots: [UInt64]) async throws -> (confirmation: widgets.Confirmation, reads: [Int]) {
        let sockets = SocketSequence()
        let pending = Mutex(roots[...])
        let reads = Mutex<[Int]>([])
        let watch = confirmer(http, sockets, clock: clock(stall: { _ in
            let count = await http.requests.count
            reads.withLock { $0.append(count) }
            let next = pending.withLock { $0.popFirst() }
            let root = try #require(next, "The watch waits again after the last root")
            try #require(sockets.sockets.last).notify(root: root)
            try await Task.sleep(for: .seconds(3_600))
        }))

        let confirmation = try await watch.confirm(submission)

        await sockets.waitUntilClosed()
        return (confirmation, reads.withLock(\.self))
    }

    private func reads(of http: HTTPResponses) async throws -> [String: Int] {
        try await http.requests.reduce(into: [:]) { counts, request in counts[try request.rpcMethod, default: 0] += 1 }
    }

    private func coordinator(over http: HTTPResponses, sockets: SocketSequence,
                             store: SigningRecoveryStore) -> any TransactionCoordinating {
        let rpc = http.client(socket: { sockets.connect($0) })
        return TransactionCoordinator(rpc: rpc, preparer: Preparer(rpc: rpc), signer: Signer(validator: PreparationValidator(rpc: rpc), store: store),
                                      submitter: Submitter(rpc: rpc), confirmer: confirmer(http, sockets))
    }

    private func clock(stall: @escaping ControlledClock.Sleep = { _ in try await Task.sleep(for: .seconds(3_600)) },
                       wait: @escaping ControlledClock.Sleep = { _ in }) -> ControlledClock {
        ControlledClock { duration in
            if duration == .seconds(30) { try await stall(duration) } else { try await wait(duration) }
        }
    }

    private func status(_ commitment: Commitment?, error: TransactionError? = nil) -> GetSignatureStatuses.Status {
        .init(slot: 405, confirmations: nil, error: error, confirmationStatus: commitment)
    }

    private func response(_ status: GetSignatureStatuses.Status?, at slot: UInt64 = 2_000) -> GetSignatureStatuses.Response {
        .init(context: Context(slot: slot), value: [status])
    }

    private func epoch(slot: UInt64, height: UInt64) -> GetEpochInfo.Response {
        .init(epoch: 1, absoluteSlot: slot, blockHeight: height)
    }
}
