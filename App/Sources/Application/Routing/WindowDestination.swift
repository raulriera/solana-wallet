/// A window's root destination, carrying only public account metadata.
nonisolated enum WindowDestination: Equatable, Sendable {
    case restoringWallets
    case walletRestorationFailed
    case onboarding
    case wallet(Account)
}
