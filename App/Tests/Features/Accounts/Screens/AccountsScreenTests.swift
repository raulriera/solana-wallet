import Observation
import SwiftUI
import Testing
import Wallet
@testable import widgets

/// Runs the accounts list in a real window, so Add Account runs in the screen's own task, as on screen.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountsScreenTests {
    /// Adding to the screen's wallet saves the wallet's next account.
    /// - Throws: A test prerequisite error.
    @Test
    func `Add Account saves the wallet's next account`() async throws {
        let wallet = try await PublicWalletAccounts()
        let addition = AccountAdditionModel()
        let screen = AccountsScreen(accounts: wallet.store.accounts, wallet: wallet.first.recoveryID, addition: addition,
                                    deletion: AccountDeletionModel())
        let hosted = try wallet.hosted(NavigationStack { screen.accountsLifecycle() })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        addition.add(to: screen.wallet)

        // The store shows the account at once; the model reports it once it's saved. The suite's time limit ends the
        // wait if it never is.
        for await added in Observations({ addition.added }) where added != nil { break }
        #expect(wallet.store.accounts.last?.path == .solana(account: 1))
        #expect(await wallet.storage.value?.count == 2)
    }
}
