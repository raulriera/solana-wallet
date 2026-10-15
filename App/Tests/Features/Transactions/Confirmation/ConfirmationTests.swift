import Foundation
import RPC
import Synchronization
import Testing
@testable import widgets

/// Verifies the real-time watch through the real client, local HTTP fixtures and sockets, and test-controlled time.
///
/// The receipt's blockhash is valid through block height 650.
struct ConfirmationTests {
    /// The second instruction's custom program error, which `{"InstructionError":[1,{"Custom":6001}]}` reports.
    private static let instructionError = TransactionError(name: "InstructionError",
                                                           details: .array([.integer(1), .object(["Custom": .integer(6001)])]))
    /// A provider's temporary server error.
    private static let unavailable = RPCError.http(statusCode: 503, retryAfter: nil)
    /// A provider's rate limit.
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")
    /// A provider's rejection of the RPC API key.
    private static let rejectedKey = RPCError.http(statusCode: 401, retryAfter: nil)
    /// A successful execution at slot 405, observed at finalized commitment.
    private static let finalizedStatus = GetSignatureStatuses.Status(slot: 405, confirmations: nil, error: nil,
                                                                     confirmationStatus: .finalized)

    private let submission = Submission(signature: ExternalFixture.signature, network: .devnet, lastValidBlockHeight: 650)

    /// Verifies a landing notification settles the watch at finalized commitment, keeping execution failures.
    /// - Parameters:
    ///   - error: The JSON of the notification's execution error.
    ///   - outcome: The expected outcome.
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

    /// Verifies the status read after subscribing settles a transaction that landed before the subscription started,
    /// without waiting for the expiry check that runs alongside it.
    /// - Parameters:
    ///   - error: The finalized execution failure, if any.
    ///   - outcome: The expected outcome.
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

    /// Verifies a status that isn't finalized yet keeps the watch open until the transaction lands.
    /// - Parameter commitment: A processed, confirmed, or unavailable confirmation level.
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

    /// Verifies roots read the finalized block height only from the slot at which it can first pass the expiry,
    /// and that a missing status after expiry reports the transaction as dropped.
    @Test(.timeLimit(.minutes(1)))
    func `Roots check the expiry only from the scheduled slot, then a missing status reports a drop`() async throws {
        // Height 600 at slot 1,000 leaves 50 blocks, so slot 1,051 is the first that can pass height 650;
        // height 640 at slot 1,051 moves the next check to slot 1,062.
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(nil, at: 1_062)], epochs: [
            epoch(slot: 1_000, height: 600), epoch(slot: 1_051, height: 640), epoch(slot: 1_062, height: 651),
        ])

        let (confirmation, reads) = try await confirm(over: http, pacing: [1_010, 1_050, 1_051, 1_061, 1_062])

        #expect(confirmation == Confirmation(submission: submission, slot: nil, outcome: .dropped))
        // Roots 1,010, 1,050, and 1,061 read nothing; root 1,051 reads the epoch, and root 1,062 settles the watch.
        #expect(reads == [2, 2, 2, 3, 3])
        #expect(try await self.reads(of: http) == ["getSignatureStatuses": 2, "getEpochInfo": 3])
    }

    /// Verifies a root ahead of the finalized slot schedules the next check from that root, so later roots cause no reads.
    @Test(.timeLimit(.minutes(1)))
    func `A root ahead of the finalized slot causes no extra reads`() async throws {
        // At root 1,100, finalized slot 1,060 has 40 blocks left, so the next check is at root 1,141.
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

    /// Verifies a status found after the blockhash expired settles the watch with that status's outcome.
    @Test(.timeLimit(.minutes(1)))
    func `A status found after expiry settles the watch with its outcome`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(status(.finalized, error: Self.instructionError))],
                                                  epochs: [epoch(slot: 1_000, height: 600), epoch(slot: 1_051, height: 651)])
        let sockets = SocketSequence { _ in SocketSequence.watch(then: [SocketFixture.rootNotification(1_051)]) }

        let confirmation = try await confirmer(http, sockets).confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: 405, outcome: .failed(Self.instructionError)))
        #expect(try await reads(of: http) == ["getSignatureStatuses": 2, "getEpochInfo": 2])
    }

    /// Verifies a status read from a node behind the expiry slot is read again only once roots cover the slots it lags.
    @Test(.timeLimit(.minutes(1)))
    func `A status read behind the expiry slot waits for roots to cover the lag`() async throws {
        // The read at root 1,051 comes from slot 1,041, 10 slots behind expiry slot 1,051, so the next one is at root 1,061.
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(nil, at: 1_041), response(nil, at: 1_051)],
                                                  epochs: [epoch(slot: 1_000, height: 600), epoch(slot: 1_051, height: 651)])

        let (confirmation, reads) = try await confirm(over: http, pacing: [1_051, 1_060, 1_061])

        #expect(confirmation == Confirmation(submission: submission, slot: nil, outcome: .dropped))
        // Root 1,060 reads nothing.
        #expect(reads == [2, 4, 4])
        #expect(try await self.reads(of: http) == ["getSignatureStatuses": 3, "getEpochInfo": 2])
    }

    /// Verifies a status that isn't finalized after the blockhash expired keeps the watch open, the next root reads it
    /// again, and a missing status then reports the transaction as dropped.
    @Test(.timeLimit(.minutes(1)))
    func `A processed status after expiry is read again, then a missing one reports a drop`() async throws {
        // At root 1,051, height 651 proves the expiry, and the final read at expiry slot 1,051 finds only a processed status.
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(status(.processed), at: 1_051), response(nil)],
                                                  epochs: [epoch(slot: 1_000, height: 600), epoch(slot: 1_051, height: 651)])

        let (confirmation, reads) = try await confirm(over: http, pacing: [1_051, 1_052])

        #expect(confirmation == Confirmation(submission: submission, slot: nil, outcome: .dropped))
        // The watch waits for root 1,052 before it reads the status again.
        #expect(reads == [2, 4])
        #expect(try await self.reads(of: http) == ["getSignatureStatuses": 3, "getEpochInfo": 2])
    }

    /// Verifies checks due past the largest slot saturate instead of overflowing, so the watch continues until the landing.
    /// - Parameters:
    ///   - lastValidBlockHeight: The receipt's last valid block height.
    ///   - slot: The finalized slot of the epoch read.
    ///   - height: The finalized block height of the epoch read.
    ///   - methods: The expected HTTP reads by method.
    @Test(.timeLimit(.minutes(1)), arguments: [
        // At height 0, the remaining heights put the next check past the largest slot.
        (UInt64.max, UInt64(1_000), UInt64(0), ["getSignatureStatuses": 1, "getEpochInfo": 1]),
        // The blockhash expired at the largest slot; the final read is from slot 2,000, so the next one waits past it.
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

    /// Verifies that when the first expiry check finds the blockhash expired, a catch-up read from the expiry slot or later
    /// proves the drop without another status read.
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

    /// Verifies a reconnection after the blockhash expired reads the status once, as both the catch-up and the final read,
    /// and that a first read behind the expiry slot waits for roots past that slot, not for the first root.
    @Test(.timeLimit(.minutes(1)))
    func `A reconnection after expiry settles the watch with one status read`() async throws {
        // The catch-up read from slot 1,000 can't prove the drop at expiry slot 1,051, and the final read comes from
        // slot 1,041, 10 slots behind it, so roots before 1,061 cause no reads.
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

    /// Verifies a lost connection reconnects after two seconds and catches up on a landing it missed.
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
        // The second connection's catch-up read settles the watch, whether or not its expiry check was sent.
        #expect(try await reads(of: http)["getSignatureStatuses"] == 2)
    }

    /// Verifies reconnection waits double up to a minute after each failed attempt and reset after a subscription and
    /// its first reads succeed.
    @Test(.timeLimit(.minutes(1)))
    func `Reconnection waits double up to a minute and reset after a subscription and its first reads`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(status(.finalized))],
                                                  epochs: [epoch(slot: 1_000, height: 600)])
        // The eighth connection subscribes and reads the status and epoch, then reports a node that is behind;
        // the tenth subscribes and catches up.
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
        // The second connection's catch-up read settles the watch, whether or not its expiry check was sent.
        #expect(try await reads(of: http)["getSignatureStatuses"] == 2)
    }

    /// Verifies a connection that delivers no root for thirty seconds counts as lost and reconnects.
    @Test(.timeLimit(.minutes(1)))
    func `A connection without roots for thirty seconds reconnects`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [response(nil), response(status(.finalized))],
                                                  epochs: [epoch(slot: 1_000, height: 600)])
        let sockets = SocketSequence()
        let stalls = Mutex(0)
        let waits = Mutex<[Duration]>([])

        let confirmation = try await confirmer(http, sockets, clock: clock(stall: { _ in
            // Only the first stall timer fires; any later one never does.
            if stalls.withLock({ $0 += 1; return $0 }) > 1 { try await Task.sleep(for: .seconds(3_600)) }
        }, wait: { duration in waits.withLock { $0.append(duration) } })).confirm(submission)

        #expect(confirmation.outcome == .succeeded)
        #expect(stalls.withLock(\.self) == 1)
        #expect(waits.withLock(\.self) == [.seconds(2)])
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
        // The second connection's catch-up read settles the watch, whether or not its expiry check was sent.
        #expect(try await reads(of: http)["getSignatureStatuses"] == 2)
    }

    /// Verifies a server or transport error reconnects instead of throwing, whether it answers the subscription,
    /// the status read, or the first expiry check, and that each failed attempt doubles the wait.
    /// - Parameters:
    ///   - readError: The recoverable failure that the failing reads return, or `nil` when the subscriptions fail.
    ///   - failingMethod: The only read that fails, or `nil` when every read fails.
    ///   - connection: The responder for every connection, which fails or acknowledges the subscriptions.
    ///   - statusReads: The expected status reads; each connection's expiry check runs alongside its status read.
    @Test(.timeLimit(.minutes(1)), arguments: [
        (RPCError?.none, String?.none, SocketSequence.failing(with: Self.unavailable), 0),
        (nil, nil, SocketSequence.failing(with: RPCError.transport(.timedOut)), 0),
        // A subscription whose first reads fail doesn't reset the wait, whether the status read or the expiry check fails.
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
        // The first wait elapses at once; the second holds the watch until it's cancelled.
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

    /// Verifies a rate limit or a rejected key stops the watch without reconnecting, and the coordinator keeps the receipt.
    /// - Parameters:
    ///   - refusal: The provider's refusal, which the delivery error keeps.
    ///   - readError: The refusal when it answers the status read, or `nil` when it answers the subscription.
    ///   - connection: The responder for the connection, which refuses or acknowledges the subscriptions.
    ///   - statusReads: The expected status reads; the expiry check runs alongside the status read.
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

    /// Verifies cancelling the coordinator's watch throws a delivery error that keeps the receipt and the cancellation.
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

    /// Verifies the coordinator watches a receipt through its confirmer alone, without reading recovery or sending.
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

    /// Verifies a provider that refuses the root subscription stops the watch before any read, without reconnecting.
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

    /// Verifies a landing without its execution result stops the watch after setup, without reconnecting.
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

    /// Verifies malformed positional or ledger observations cannot become confirmations.
    ///
    /// - Parameters:
    ///   - statuses: The response's statuses for the one requested signature.
    ///   - contextSlot: The slot at which the node read them.
    @Test(.timeLimit(.minutes(1)), arguments: [
        // No status for the requested signature.
        ([GetSignatureStatuses.Status?](), 406),
        // More statuses than requested signatures.
        ([Self.finalizedStatus, nil], 406),
        // A status from a slot after the read's context slot.
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

    /// Verifies watching another network never sends the signature to the provider.
    @Test
    func `Confirmation rejects another network before subscribing or reading`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [])
        let sockets = SocketSequence()

        await #expect(throws: ConfirmerError.networkMismatch) {
            try await confirmer(http, sockets).confirm(Submission(
                signature: submission.signature, network: .mainnet, lastValidBlockHeight: submission.lastValidBlockHeight
            ))
        }

        #expect(await http.requests.isEmpty)
        #expect(sockets.sockets.isEmpty)
    }

    /// Verifies cancelling the watch while it subscribes closes the connection before any read.
    @Test(.timeLimit(.minutes(1)))
    func `Cancelling a subscription closes its connection before any read`() async throws {
        let http = try HTTPResponses.confirmation(statuses: [])
        // The connection never acknowledges the subscriptions.
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

    /// Verifies cancellation stops a watch that waits for events or to reconnect, and closes its connection.
    ///
    /// The coordinator's cancellation test covers a status read in flight.
    /// - Parameters:
    ///   - connection: The responder for every connection, which acknowledges the subscriptions or fails to connect.
    ///   - reads: The HTTP reads that finish before the cancellation.
    @Test(.timeLimit(.minutes(1)), arguments: [
        (SocketSequence.watch(), 2), (SocketSequence.failing(with: URLError(.notConnectedToInternet)), 0),
    ])
    func `Cancelling a waiting watch stops it and closes its connection`(connection: @escaping SocketFixture.Responder,
                                                                        reads: Int) async throws {
        let pending = Suspension()
        let http = try HTTPResponses.confirmation(statuses: [response(nil)], epochs: [epoch(slot: 1_000, height: 600)])
        let sockets = SocketSequence { _ in connection }
        // The first stall timer or reconnection wait holds the watch until it's cancelled.
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

    /// Creates a watch whose requests and subscriptions never reach the network.
    ///
    /// - Parameters:
    ///   - http: The fixture that answers status and epoch reads.
    ///   - sockets: The connections that answer subscriptions.
    ///   - clock: The test's clock, or `nil` for one whose stall timers never fire and whose waits elapse at once.
    /// - Returns: A watch over the real Helius client.
    private func confirmer(_ http: HTTPResponses, _ sockets: SocketSequence, clock: ControlledClock? = nil) -> Confirmer {
        Confirmer(rpc: http.client(socket: { sockets.connect($0) }), clock: clock ?? self.clock())
    }

    /// Watches the receipt over one connection that receives each root only when the watch waits for an event.
    ///
    /// Each wait records the HTTP reads so far, so a test can tell which root caused each read.
    /// - Parameters:
    ///   - http: The fixture that answers status and epoch reads.
    ///   - roots: The roots to deliver, one at each wait.
    /// - Returns: The settled watch, and the HTTP read count at each wait.
    /// - Throws: The watch's error, or a test failure when the watch waits again after the last root.
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
            // The root ends the wait, which cancels this timer.
            try await Task.sleep(for: .seconds(3_600))
        }))

        let confirmation = try await watch.confirm(submission)

        await sockets.waitUntilClosed()
        return (confirmation, reads.withLock(\.self))
    }

    /// Counts the watch's HTTP reads by method.
    ///
    /// Each connection's status read and expiry check run together, so their order can differ between runs.
    /// - Parameter http: The fixture that answered the reads.
    /// - Returns: The number of reads of each method.
    /// - Throws: A test failure when a request isn't JSON-RPC.
    private func reads(of http: HTTPResponses) async throws -> [String: Int] {
        try await http.requests.reduce(into: [:]) { counts, request in counts[try request.rpcMethod, default: 0] += 1 }
    }

    /// Creates a coordinator whose services share one HTTP fixture, one socket sequence, and one recovery store.
    ///
    /// - Parameters:
    ///   - http: The fixture that serves every RPC request.
    ///   - sockets: The connections that answer subscriptions.
    ///   - store: The recovery store that records reads.
    /// - Returns: A coordinator whose watch has no wall-time delays.
    private func coordinator(over http: HTTPResponses, sockets: SocketSequence,
                             store: SigningRecoveryStore) -> any TransactionCoordinating {
        let rpc = http.client(socket: { sockets.connect($0) })
        return TransactionCoordinator(rpc: rpc, preparer: Preparer(rpc: rpc), signer: Signer(validator: PreparationValidator(rpc: rpc), store: store),
                                      submitter: Submitter(rpcs: [rpc]), confirmer: confirmer(http, sockets))
    }

    /// Creates a clock that tells 30-second stall timers apart from reconnection waits.
    ///
    /// - Parameters:
    ///   - stall: Handles each stall timer; by default, it never fires.
    ///   - wait: Handles each reconnection wait; by default, it elapses at once.
    /// - Returns: A clock with no wall-time delays.
    private func clock(stall: @escaping ControlledClock.Sleep = { _ in try await Task.sleep(for: .seconds(3_600)) },
                       wait: @escaping ControlledClock.Sleep = { _ in }) -> ControlledClock {
        ControlledClock { duration in
            if duration == .seconds(30) { try await stall(duration) } else { try await wait(duration) }
        }
    }

    /// Creates an execution status without inferring finality from a missing confirmation count.
    ///
    /// - Parameters:
    ///   - commitment: The observed commitment, including an unavailable level.
    ///   - error: The execution failure, if any.
    /// - Returns: A status at slot 405 with its explicit commitment and outcome.
    private func status(_ commitment: Commitment?, error: TransactionError? = nil) -> GetSignatureStatuses.Status {
        .init(slot: 405, confirmations: nil, error: error, confirmationStatus: commitment)
    }

    /// Wraps a positional status in the provider's ledger context.
    ///
    /// - Parameters:
    ///   - status: The observation, or `nil` for an unknown transaction.
    ///   - slot: The context slot at which the node read it.
    /// - Returns: A one-signature response.
    private func response(_ status: GetSignatureStatuses.Status?, at slot: UInt64 = 2_000) -> GetSignatureStatuses.Response {
        .init(context: Context(slot: slot), value: [status])
    }

    /// Creates a finalized epoch observation.
    ///
    /// - Parameters:
    ///   - slot: The finalized slot.
    ///   - height: The finalized block height.
    /// - Returns: An observation in epoch 1.
    private func epoch(slot: UInt64, height: UInt64) -> GetEpochInfo.Response {
        .init(epoch: 1, absoluteSlot: slot, blockHeight: height)
    }
}
