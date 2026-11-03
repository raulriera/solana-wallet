import Foundation
import Observation
import Storage

/// The navigation state of one window.
@MainActor
@Observable
final class WindowModel {
    /// The identity of the account that the window chose, or `nil` for onboarding.
    private(set) var accountID: Account.ID?
    private var isStarted = false
    private let accounts: AccountStore

    var destination: WindowDestination {
        guard isStarted else { return .restoringWallets }
        guard accounts.phase == .loaded else { return .walletRestorationFailed }
        guard let accountID else { return .onboarding }
        let account = accounts.accounts.first { $0.id == accountID } ?? accounts.accounts.first
        return account.map(WindowDestination.wallet) ?? .onboarding
    }

    /// The account that the window shows, or `nil` when it shows no wallet.
    var account: Account? {
        get {
            guard case .wallet(let account) = destination else { return nil }
            return account
        }
        set { accountID = newValue?.id }
    }

    /// Accesses the account that the window shows, or a fallback when it shows none.
    ///
    /// - Parameter fallback: The account to return when the window shows none.
    /// - Returns: The shown account, or `fallback`.
    subscript(account fallback: Account) -> Account {
        get { account ?? fallback }
        set { account = newValue }
    }

    /// Creates a window's navigation state.
    ///
    /// - Parameter accounts: The saved accounts.
    init(accounts: AccountStore) {
        self.accounts = accounts
    }

    /// Loads the saved accounts and chooses the window's account.
    ///
    /// - Parameter restored: The identity of the account that the window showed last, if any.
    func restore(preferring restored: Account.ID?) async {
        guard !isStarted || accounts.phase != .loaded else { return }
        await accounts.load()
        guard !Task.isCancelled else { return }
        if accountID == nil { accountID = restored ?? accounts.accounts.first?.id }
        isStarted = true
    }
}
