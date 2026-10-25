import SwiftUI
import Testing
@testable import widgets

/// Runs renames in a real window, so a failure shows its alert as on screen.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountRenameLifecycleTests {
    /// A name that can't be saved shows the alert that explains it, and the account keeps its saved name.
    /// - Throws: A test prerequisite error.
    @Test
    func `A failed rename shows its alert`() async throws {
        let wallet = try await PublicWalletAccounts()
        await wallet.storage.failSaving()
        let rename = AccountRenameModel()
        let screen = AccountScreen(account: wallet.first, canDelete: true, rename: rename,
                                           deletion: AccountDeletionModel())
        let hosted = try wallet.hosted(NavigationStack { screen.accountRenameLifecycle() })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        rename.rename(wallet.first.id, to: "Savings")

        #expect(try await hosted.presentsViewController())
        #expect(rename.error == .notRenamed)
        #expect(wallet.store.accounts == [wallet.first])
    }
}
