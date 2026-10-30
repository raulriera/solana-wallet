import SwiftUI
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountAdditionLifecycleTests {
    @Test
    func `A failed addition shows its alert`() async throws {
        let wallet = try await PublicWalletAccounts()
        await wallet.storage.failSaving()
        let addition = AccountAdditionModel()
        let screen = AccountsScreen(accounts: wallet.store.accounts, selection: .constant(wallet.first),
                                    addition: addition, deletion: AccountDeletionModel(), path: .constant([]))
        let hosted = try wallet.hosted(NavigationStack { screen.accountsLifecycle() })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        addition.add(to: wallet.first.recoveryID)

        #expect(try await hosted.presentsViewController())
        #expect(addition.error == .notAdded)
        #expect(wallet.store.accounts == [wallet.first])
    }
}
