import Transactions
import Wallet

/// An account that signs a reviewed transaction.
nonisolated enum Authority: Sendable {
    /// A saved account that signs after authentication.
    case account(Account)
    /// An in-memory one-time account that signs without authentication.
    case oneTime(OneTimeAccount)

    var address: Address {
        get throws {
            switch self {
            case .account(let account): account.address
            case .oneTime(let account): try Address(account.address)
            }
        }
    }
}
