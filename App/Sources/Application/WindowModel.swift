import Foundation
import Observation
import Storage

/// Owns one window's navigation: the account that the window chose, by identity, and the destination that the saved
/// accounts give it; the services stay shared.
@MainActor
@Observable
final class WindowModel {
    /// The account that the window chose and its wallet, or `nil` while the window shows onboarding.
    private(set) var selection: Selection?
    /// Whether the window's startup has read the saved accounts once.
    private var isStarted = false
    private let accounts: AccountStore

    /// The window's root destination, which the saved accounts give, so another window's rename or deletion shows at
    /// once.
    ///
    /// The window shows nothing until its startup ends, and a retryable error while the saved accounts can't be read.
    /// It shows the chosen account, else its wallet's first account, else the first saved account, and onboarding
    /// without a selection or a saved account.
    var destination: WindowDestination {
        guard isStarted else { return .restoringWallets }
        guard accounts.phase == .loaded else { return .walletRestorationFailed }
        guard let selection else { return .onboarding }
        let account = accounts.accounts.first { $0.id == selection.accountID }
            ?? accounts.accounts(inWallet: selection.walletID).first
            ?? accounts.accounts.first
        return account.map(WindowDestination.wallet) ?? .onboarding
    }

    /// The saved account that the window shows, or `nil` while it shows no wallet.
    ///
    /// Setting an account chooses it in this window only, and the window reopens it after the system ends the app;
    /// setting `nil` forgets the choice, so the window shows onboarding.
    var account: Account? {
        get {
            guard case .wallet(let account) = destination else { return nil }
            return account
        }
        set { selection = newValue.map(Selection.init) }
    }

    /// The account that the window shows, or `fallback` once a reset leaves the wallet, so its closing screens can
    /// still read their binding; setting it chooses that account.
    /// - Parameter fallback: The account that the wallet's screens showed.
    subscript(account fallback: Account) -> Account {
        get { account ?? fallback }
        set { account = newValue }
    }

    /// Creates the window's navigation over the saved accounts, before its startup reads them.
    /// - Parameter accounts: The saved accounts that every window shares, which finish the launch cleanup of
    ///   unreferenced recovery before they're read.
    init(accounts: AccountStore) {
        self.accounts = accounts
    }

    /// Reads the saved accounts and chooses the window's account, else the first saved account, until a read
    /// succeeds; a window that read them keeps its selection, also while it shows onboarding.
    ///
    /// A cancelled read changes nothing, and an account chosen during the read wins over the restored one. A failed
    /// read preserves storage and leaves the accounts unreadable, which the window can retry.
    /// - Parameter restored: The account that the window chose before the system ended the app, if any.
    func restore(preferring restored: Selection?) async {
        guard !isStarted || accounts.phase != .loaded else { return }
        await accounts.load()
        guard !Task.isCancelled else { return }
        if selection == nil { selection = restored ?? accounts.accounts.first.map(Selection.init) }
        isStarted = true
    }
}

extension WindowModel {
    /// The identities of a window's chosen account and its wallet, which outlive the account's other details.
    nonisolated struct Selection: Equatable, Sendable {
        /// The chosen account's identity.
        let accountID: Account.ID
        /// The recovery identifier of the chosen account's wallet, whose first account the window shows once the
        /// chosen account is deleted.
        let walletID: UUID

        /// Chooses an account by its identities.
        /// - Parameters:
        ///   - accountID: The account's identity.
        ///   - walletID: The recovery identifier of the account's wallet.
        init(accountID: Account.ID, walletID: UUID) {
            self.accountID = accountID
            self.walletID = walletID
        }

        /// Chooses a saved account.
        /// - Parameter account: The account.
        init(_ account: Account) {
            self.init(accountID: account.id, walletID: account.recoveryID)
        }
    }
}
