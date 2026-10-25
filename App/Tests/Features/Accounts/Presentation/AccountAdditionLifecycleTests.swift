import SwiftUI
import Testing
@testable import widgets

/// Runs account additions in a real window, so a failure shows its alert as on screen.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountAdditionLifecycleTests {
    /// An account that can't be saved shows the alert that explains it.
    /// - Throws: A test prerequisite error.
    @Test
    func `A failed addition shows its alert`() async throws {
        let wallet = try await PublicWalletAccounts()
        await wallet.storage.failSaving()
        let addition = AccountAdditionModel()
        let screen = AccountsScreen(accounts: wallet.store.accounts, wallet: wallet.first.recoveryID, addition: addition,
                                    deletion: AccountDeletionModel())
        let hosted = try wallet.hosted(NavigationStack { screen.accountsLifecycle() })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        addition.add(to: wallet.first.recoveryID)

        #expect(try await hosted.presentsViewController())
        #expect(addition.error == .notAdded)
        #expect(wallet.store.accounts == [wallet.first])
    }
}
