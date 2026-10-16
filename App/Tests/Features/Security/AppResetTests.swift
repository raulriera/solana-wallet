import Foundation
import Testing
@testable import widgets

/// Verifies the reset's deletion order, its window signal, and retries, without touching real storage.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppResetTests {
    /// Secrets go first, and every window hears about the reset only once everything is deleted.
    @Test
    func `Reset deletes recovery first, then private balances, then wallets, then the API key, then the provider settings`() async throws {
        let storage = ResetStorage()
        let revision = Revision()

        try await AppReset(storage: storage, revision: revision).reset()

        #expect(await storage.deletions == ResetStorage.Step.allCases)
        #expect(revision.value == 1)
    }

    /// A failed step stops the reset and keeps windows where they are; trying again finishes it.
    /// - Parameter step: The store whose first deletion fails.
    @Test(arguments: ResetStorage.Step.allCases)
    func `Retrying after a failed step finishes the reset`(_ step: ResetStorage.Step) async throws {
        let storage = ResetStorage(failingOnce: step)
        let revision = Revision()
        let reset = AppReset(storage: storage, revision: revision)
        let order = ResetStorage.Step.allCases

        await #expect(throws: CocoaError.self) { try await reset.reset() }
        #expect(await storage.deletions == Array(order.prefix { $0 != step }))
        #expect(revision.value == 0)

        try await reset.reset()
        #expect(await Array(storage.deletions.suffix(order.count)) == order)
        #expect(revision.value == 1)
    }
}
