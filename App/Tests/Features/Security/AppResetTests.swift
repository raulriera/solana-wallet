import Foundation
import Testing
@testable import widgets

/// Verifies the reset's deletion order, its window signal, and retries, without touching real storage.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppResetTests {
    /// Secrets go first, and every window hears about the reset only once everything is deleted.
    @Test
    func `Reset deletes recovery first, then wallets, then the API key`() async throws {
        let storage = ResetStorage()
        let revision = Revision()

        try await AppReset(recovery: storage, accounts: storage, providerKeys: storage, revision: revision).reset()

        #expect(await storage.deletions == [.recovery, .wallets, .key])
        #expect(revision.value == 1)
    }

    /// A failed step stops the reset and keeps windows where they are; trying again finishes it.
    /// - Parameter step: The store whose first deletion fails.
    @Test(arguments: [ResetStorage.Step.recovery, .wallets, .key])
    func `Retrying after a failed step finishes the reset`(_ step: ResetStorage.Step) async throws {
        let storage = ResetStorage(failingOnce: step)
        let revision = Revision()
        let reset = AppReset(recovery: storage, accounts: storage, providerKeys: storage, revision: revision)
        let order: [ResetStorage.Step] = [.recovery, .wallets, .key]

        await #expect(throws: CocoaError.self) { try await reset.reset() }
        #expect(await storage.deletions == Array(order.prefix { $0 != step }))
        #expect(revision.value == 0)

        try await reset.reset()
        #expect(await Array(storage.deletions.suffix(order.count)) == order)
        #expect(revision.value == 1)
    }
}
