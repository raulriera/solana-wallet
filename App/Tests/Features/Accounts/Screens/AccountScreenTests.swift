import Observation
import SwiftUI
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountScreenTests {
    @Observable
    final class Navigation {
        var path: [AccountsRoute]

        init(_ path: [AccountsRoute]) {
            self.path = path
        }
    }

    @Test
    func `A saved name closes the screen`() async throws {
        let wallet = try await PublicWalletAccounts()
        let rename = AccountRenameModel()
        let account = wallet.first
        let navigation = Navigation([.account(account.id)])
        let hosted = try wallet.hosted(NavigationStack(path: Bindable(navigation).path) {
            Color.clear
                .navigationDestination(for: AccountsRoute.self) { _ in
                    AccountScreen(account: account, canDelete: true, rename: rename,
                                           deletion: AccountDeletionModel())
                        .accountRenameLifecycle()
                }
        })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        rename.rename(account.id, to: "Savings")

        for await path in Observations({ navigation.path }) where path.isEmpty { break }
        #expect(wallet.store.accounts.first?.name == "Savings")
        #expect(await wallet.storage.value?.first?.customName == "Savings")
    }
}
