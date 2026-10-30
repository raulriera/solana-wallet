import SwiftUI
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountRenameLifecycleTests {
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
