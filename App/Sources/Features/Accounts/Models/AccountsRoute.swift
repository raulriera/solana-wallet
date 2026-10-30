import Foundation

/// A screen that Settings > Accounts pushes.
nonisolated enum AccountsRoute: Hashable {
    /// The screen of the account with this identifier.
    case account(UUID)
}
