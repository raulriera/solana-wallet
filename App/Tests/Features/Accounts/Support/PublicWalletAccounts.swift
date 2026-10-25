import Foundation
import SwiftUI
import Testing
import Wallet
@testable import widgets

/// The public test wallet's first account, saved and read, and account creation from the wallet's recovery.
@MainActor
struct PublicWalletAccounts {
    /// The wallet's first account, at `m/44'/501'/0'/0'`.
    let first: widgets.Account
    /// The saved accounts, which start with ``first``.
    let storage: StoredValue<[widgets.Account]>
    /// The shared accounts, already read from ``storage``.
    let store: AccountStore
    /// The wallet's recovery, which counts its reads.
    let recovery: SecurityRecoveryStore
    /// Creates accounts from ``recovery``.
    let creation: AccountCreation

    /// Derives the first account, saves it, and reads it back.
    /// - Parameter readError: The error every recovery read throws, such as a cancelled prompt.
    /// - Throws: A fixture error.
    init(readError: (any Error)? = nil) async throws {
        let recoveryID = UUID()
        first = try await PublicWallet.account(recoveryID: recoveryID)
        storage = StoredValue([first])
        store = AccountStore.inMemory(storage)
        await store.load()
        recovery = SecurityRecoveryStore(records: [recoveryID: try PublicWallet.recovery()], readError: readError)
        creation = AccountCreation(recovery: recovery, wallet: Wallet())
    }

    /// Shows a view in a real window with the wallet's accounts and account creation in its environment.
    /// - Parameter content: The view under test.
    /// - Returns: The window, which the test closes.
    /// - Throws: A failed prerequisite when the test host has no active window scene.
    func hosted(_ content: some View) throws -> HostedWindow<some View> {
        try HostedWindow(content.environment(store).environment(\.accountCreation, creation))
    }
}
