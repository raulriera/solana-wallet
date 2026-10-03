import Foundation

/// A window's root destination, carrying only a public account identifier.
nonisolated enum WindowDestination: Equatable, Sendable {
    case restoringWallets
    case walletRestorationFailed
    case onboarding
    case wallet(accountID: UUID)
}
