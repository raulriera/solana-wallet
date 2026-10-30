/// A window's root destination, carrying only public account metadata.
nonisolated enum WindowDestination: Equatable, Sendable, Identifiable {
    case restoringWallets
    case walletRestorationFailed
    case onboarding
    case wallet(Account)

    /// A destination's identity: its case and its account's identity, so a renamed account stays the same destination.
    enum ID: Hashable, Sendable {
        case restoringWallets
        case walletRestorationFailed
        case onboarding
        case wallet(Account.ID)
    }

    /// The destination's identity, without the account's name.
    var id: ID {
        switch self {
        case .restoringWallets: .restoringWallets
        case .walletRestorationFailed: .walletRestorationFailed
        case .onboarding: .onboarding
        case .wallet(let account): .wallet(account.id)
        }
    }
}
