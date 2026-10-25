import Foundation

/// A screen that Settings > Accounts pushes.
nonisolated enum AccountsRoute: Hashable {
    /// An account's name, address, and path, to rename it.
    case account(UUID)
}
