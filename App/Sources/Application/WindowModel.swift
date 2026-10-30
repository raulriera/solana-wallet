import Foundation
import Observation
import Storage

/// The navigation state of one window.
@MainActor
@Observable
final class WindowModel {
    /// The account that the window chose and its wallet, or `nil` for onboarding.
    private(set) var selection: Selection?
    private var isStarted = false
    private let accounts: AccountStore

    var destination: WindowDestination {
        guard isStarted else { return .restoringWallets }
        guard accounts.phase == .loaded else { return .walletRestorationFailed }
        guard let selection else { return .onboarding }
        let account = accounts.accounts.first { $0.id == selection.accountID }
            ?? accounts.accounts(inWallet: selection.walletID).first
            ?? accounts.accounts.first
        return account.map(WindowDestination.wallet) ?? .onboarding
    }

    /// The account that the window shows, or `nil` when it shows no wallet.
    var account: Account? {
        get {
            guard case .wallet(let account) = destination else { return nil }
            return account
        }
        set { selection = newValue.map(Selection.init) }
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
    /// - Parameter restored: The account that the window showed last, if any.
    func restore(preferring restored: Selection?) async {
        guard !isStarted || accounts.phase != .loaded else { return }
        await accounts.load()
        guard !Task.isCancelled else { return }
        if selection == nil { selection = restored ?? accounts.accounts.first.map(Selection.init) }
        isStarted = true
    }
}

extension WindowModel {
    /// The identities of a window's chosen account and its wallet.
    nonisolated struct Selection: Equatable, Sendable {
        let accountID: Account.ID
        /// The recovery identifier of the account's wallet.
        let walletID: UUID

        /// Creates a selection from an account's identities.
        ///
        /// - Parameters:
        ///   - accountID: The account's identity.
        ///   - walletID: The recovery identifier of the account's wallet.
        init(accountID: Account.ID, walletID: UUID) {
            self.accountID = accountID
            self.walletID = walletID
        }

        /// Creates a selection of a saved account.
        ///
        /// - Parameter account: The account to select.
        init(_ account: Account) {
            self.init(accountID: account.id, walletID: account.recoveryID)
        }
    }
}
