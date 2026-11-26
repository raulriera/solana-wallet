import Foundation
import Observation
import SwiftUI
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionResumptionTests {
    @Test
    func `A window that becomes active resumes the pending watches`() async throws {
        let sent = try PendingPayment(from: UUID())
        let scene = ResumingScene(.background)
        let hosted = try HostedWindow(TransactionResumptionRoot(scene: scene, transactions: sent.transactions))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        scene.phase = .active

        #expect(await sent.transactions.settledStatus(of: sent.record) == .succeeded(slot: 405))
        await sent.sockets.waitUntilClosed()
    }

    @Test
    func `A new provider connection retries a failed watch`() async throws {
        let fixture = try SigningFixture()
        let record = TransactionRecord.fixture(.payment, signature: "pending", account: UUID())
        let sockets = SocketSequence()
        let coordinator = try LocalTransactions(fixture: fixture, statuses: [.status(.finalized)],
                                                sockets: sockets).coordinator
        let (attempts, attempted) = AsyncStream.makeStream(of: Void.self)
        var fails = true
        let transactions = TransactionStore.inMemory(StoredValue([record])) { _ in
            attempted.yield()
            guard !fails else {
                fails = false
                throw TransactionCoordinatorError.unsupportedNetwork
            }
            return coordinator
        }
        let scene = ResumingScene(.active)
        await scene.rpcStore.load()
        let hosted = try HostedWindow(TransactionResumptionRoot(scene: scene, transactions: transactions))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        for await _ in attempts { break }

        try await scene.rpcStore.select(.helius)

        #expect(await transactions.settledStatus(of: record) == .succeeded(slot: 405))
        await sockets.waitUntilClosed()
    }
}
