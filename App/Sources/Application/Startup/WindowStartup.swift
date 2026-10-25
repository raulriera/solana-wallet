import Foundation
import Storage

/// Selects a window's initial destination from the saved accounts, without reading recovery material.
@MainActor
struct WindowStartup: WindowStarting {
    private let accounts: AccountStore
    private let router: any WindowRouting

    /// Connects the shared accounts to the owning window's navigation.
    /// - Parameters:
    ///   - accounts: The saved accounts, which finish the launch cleanup of unreferenced recovery before they're read.
    ///   - router: The window whose initial destination is unresolved.
    init(accounts: AccountStore, router: any WindowRouting) {
        self.accounts = accounts
        self.router = router
    }

    /// Opens the window's restored account while it is still saved, otherwise the first saved account,
    /// or onboarding after a successful empty read and cleanup.
    /// Read and cleanup failures preserve storage and expose only a retryable destination.
    /// - Parameter accountID: The account this window showed before the system ended the app, if any.
    func restore(preferring accountID: UUID?) async {
        guard !Task.isCancelled, canRestore else { return }
        await accounts.load()
        guard !Task.isCancelled, canRestore else { return }
        guard accounts.phase == .loaded else {
            router.route(to: .walletRestorationFailed)
            return
        }
        let saved = accounts.accounts
        let account = saved.first { $0.id == accountID } ?? saved.first
        router.route(to: account.map { .wallet($0) } ?? .onboarding)
    }

    /// Resolved windows retain their selection when lifecycle tasks run again.
    private var canRestore: Bool {
        router.destination == .restoringWallets || router.destination == .walletRestorationFailed
    }
}
