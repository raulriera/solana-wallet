import Observation
import SwiftUI
import Testing
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountsScreenTests {
    @Test
    func `Add Account saves the wallet's next account`() async throws {
        let wallet = try await ThrowawayWalletAccounts()
        let addition = AccountAdditionModel()
        let screen = AccountsScreen(accounts: wallet.store.accounts, selection: .constant(wallet.first),
                                    addition: addition, deletion: AccountDeletionModel(), path: .constant([]))
        let hosted = try wallet.hosted(NavigationStack { screen.accountsLifecycle() })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        addition.add(to: wallet.first.recoveryID)

        for await added in Observations({ addition.added }) where added != nil { break }
        #expect(wallet.store.accounts.last?.path == .solana(account: 1))
        #expect(await wallet.storage.value?.count == 2)
    }
}
