/// Selects a window's initial destination without reading or changing recovery material.
@MainActor
struct WindowStartup: WindowStarting {
    private let accounts: any AccountStoring
    private let router: any WindowRouting

    /// Connects shared public storage to the owning window's navigation.
    /// - Parameters:
    ///   - accounts: Existing public account metadata.
    ///   - router: The window whose initial destination is unresolved.
    init(accounts: any AccountStoring, router: any WindowRouting) {
        self.accounts = accounts
        self.router = router
    }

    /// Opens the first saved account, or onboarding after a successful empty read.
    /// Read failures preserve storage and expose only a retryable destination.
    func restore() async {
        guard canRestore else { return }
        do {
            try Task.checkCancellation()
            let saved = try await accounts.load()
            try Task.checkCancellation()
            guard canRestore else { return }
            router.route(to: saved.first.map { .wallet(accountID: $0.id) } ?? .onboarding)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, canRestore else { return }
            router.route(to: .walletRestorationFailed)
        }
    }

    /// Resolved windows retain their selection when lifecycle tasks run again.
    private var canRestore: Bool {
        router.destination == .restoringWallets || router.destination == .walletRestorationFailed
    }
}
