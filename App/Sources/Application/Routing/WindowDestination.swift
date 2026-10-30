/// A window's root destination.
nonisolated enum WindowDestination: Equatable, Sendable, Identifiable {
    case restoringWallets
    case walletRestorationFailed
    case onboarding
    case wallet(Account)

    /// The identity of a window destination.
    enum ID: Hashable, Sendable {
        case restoringWallets
        case walletRestorationFailed
        case onboarding
        case wallet(Account.ID)
    }

    var id: ID {
        switch self {
        case .restoringWallets: .restoringWallets
        case .walletRestorationFailed: .walletRestorationFailed
        case .onboarding: .onboarding
        case .wallet(let account): .wallet(account.id)
        }
    }
}
