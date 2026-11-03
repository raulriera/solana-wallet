import Foundation
import Observation
@testable import RPC
import SwiftUI
import Testing
import Transactions
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

        #expect(await sent.transactions.settledStatus(of: sent.record) == .succeeded)
        await sent.sockets.waitUntilClosed()
    }

    @Test
    func `A new provider connection retries a failed watch`() async throws {
        let fixture = try SigningFixture()
        let record = TransactionRecord.fixture(.payment(recipient: fixture.transfer.accounts[1].address, mint: nil,
                                                        units: 1),
                                               signature: "pending", account: UUID())
        let sockets = SocketSequence()
        let coordinator = try LocalTransactions(fixture: fixture, statuses: [.status(.finalized)],
                                                sockets: sockets).coordinator
        let (attempts, attempted) = AsyncStream.makeStream(of: Void.self)
        var fails = true
        let transactions = TransactionStore.inMemory([record.key: StoredValue([record])],
                                                     pending: StoredValue([record.key])) { _ in
            attempted.yield()
            guard !fails else {
                fails = false
                throw TransactionCoordinatorError.unsupportedNetwork
            }
            return coordinator
        }
        let scene = ResumingScene(.active)
        await scene.providers.load()
        let hosted = try HostedWindow(TransactionResumptionRoot(scene: scene, transactions: transactions))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        for await _ in attempts { break }

        try await scene.providers.select(.helius)

        #expect(await transactions.settledStatus(of: record) == .succeeded)
        await sockets.waitUntilClosed()
    }
}
