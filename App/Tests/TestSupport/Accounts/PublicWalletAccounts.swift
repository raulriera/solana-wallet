import Foundation
import SwiftUI
import Testing
import Wallet
@testable import widgets

@MainActor
struct PublicWalletAccounts {
    let first: widgets.Account
    let storage: StoredValue<[widgets.Account]>
    let store: AccountStore
    let recovery: SecurityRecoveryStore
    let creation: AccountCreation
    let transactions = TransactionStore.unused

    init(readError: (any Error)? = nil) async throws {
        let recoveryID = UUID()
        first = try await PublicWallet.account(recoveryID: recoveryID)
        storage = StoredValue([first])
        store = AccountStore.inMemory(storage)
        await store.load()
        recovery = SecurityRecoveryStore(records: [recoveryID: try PublicWallet.recovery()], readError: readError)
        creation = AccountCreation(recovery: recovery, wallet: Wallet())
    }

    func hosted(_ content: some View) throws -> HostedWindow<some View> {
        try HostedWindow(content.environment(self))
    }
}

extension View {
    func environment(_ wallet: PublicWalletAccounts) -> some View {
        environment(wallet.store).environment(\.accountCreation, wallet.creation).environment(wallet.transactions)
    }
}
