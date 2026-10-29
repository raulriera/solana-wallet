import Observation
import SwiftUI
import Testing
@testable import widgets

/// Runs the accounts list's changes in a real window, as on screen.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountsLifecycleTests {
    /// A deletion confirmed on an account's screen runs from the list and saves.
    /// - Throws: A test prerequisite error.
    @Test
    func `The list runs a confirmed deletion`() async throws {
        let wallet = try await PublicWalletAccounts()
        let deletion = AccountDeletionModel()
        let screen = AccountsScreen(accounts: wallet.store.accounts, selection: .constant(wallet.first),
                                    addition: AccountAdditionModel(), deletion: deletion, path: .constant([]))
        let hosted = try wallet.hosted(NavigationStack { screen.accountsLifecycle() })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        deletion.delete(wallet.first.id)

        // The suite's time limit ends the wait if the deletion never finishes.
        for await attempt in Observations({ deletion.attempt }) where attempt == nil { break }
        #expect(wallet.store.accounts.isEmpty)
        #expect(await wallet.storage.value == [])
        #expect(deletion.error == nil)
    }
}
