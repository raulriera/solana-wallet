import Observation
import SwiftUI
import Testing
@testable import widgets

/// Runs an account's screen in a real window, so a saved name closes it as on screen.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountScreenTests {
    /// The screens pushed on the test's navigation stack.
    @Observable
    final class Navigation {
        var path: [AccountsRoute]

        /// Starts with the given screens pushed.
        /// - Parameter path: The pushed screens.
        init(_ path: [AccountsRoute]) {
            self.path = path
        }
    }

    /// Saving a new name saves it and closes the screen.
    /// - Throws: A test prerequisite error.
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

        // The suite's time limit ends the wait if the screen never closes.
        for await path in Observations({ navigation.path }) where path.isEmpty { break }
        #expect(wallet.store.accounts.first?.name == "Savings")
        #expect(await wallet.storage.value?.first?.customName == "Savings")
    }
}
