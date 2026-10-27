import Foundation
import Observation
@testable import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

/// Runs the resumption of pending watches in a real window, as each window's root does.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionResumptionTests {
    /// A window whose scene becomes active watches a pending record that nothing watched, as after a relaunch, until it
    /// settles.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `A window that becomes active resumes the pending watches`() async throws {
        let sent = try PendingPayment(from: UUID())
        let scene = ResumingScene(.background)
        let hosted = try HostedWindow(TransactionResumptionRoot(scene: scene, transactions: sent.transactions))
        defer { hosted.close() }
        // Closing the window before it finishes appearing would interrupt UIKit's appearance transition.
        try #require(try await hosted.appears())

        scene.phase = .active

        #expect(await sent.transactions.settledStatus(of: sent.record) == .succeeded)
        await sent.sockets.waitUntilClosed()
    }

    /// A new provider connection watches a pending record again after its watch stopped with an error that no caller
    /// read, since only a change that may fix the error retries it.
    /// - Throws: A fixture or test prerequisite error.
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
        // The first watch fails at once, as it can't create the coordinator.
        let transactions = TransactionStore.inMemory([record.key: StoredValue([record])],
                                                     pending: StoredValue([record.key])) { _ in
            attempted.yield()
            guard !fails else {
                fails = false
                throw SubmitterError.noProviders
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
