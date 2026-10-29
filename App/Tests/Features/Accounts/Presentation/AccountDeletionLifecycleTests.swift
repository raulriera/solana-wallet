import SwiftUI
import Testing
@testable import widgets

/// Runs deletions in a real window, so a failure shows its alert as on screen.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountDeletionLifecycleTests {
    /// A deletion that can't be saved shows the alert that explains it, and the account stays.
    /// - Throws: A test prerequisite error.
    @Test
    func `A failed deletion shows its alert`() async throws {
        let wallet = try await PublicWalletAccounts()
        await wallet.storage.failSaving()
        let deletion = AccountDeletionModel()
        let screen = AccountsScreen(accounts: wallet.store.accounts, selection: .constant(wallet.first),
                                    addition: AccountAdditionModel(), deletion: deletion, path: .constant([]))
        let hosted = try wallet.hosted(NavigationStack { screen.accountsLifecycle() })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        deletion.delete(wallet.first.id)

        #expect(try await hosted.presentsViewController())
        #expect(deletion.error == .notDeleted)
        #expect(wallet.store.accounts == [wallet.first])
    }
}
