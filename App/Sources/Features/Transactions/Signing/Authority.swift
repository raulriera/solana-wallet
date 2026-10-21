import Transactions
import Wallet

/// A local signer selected for a reviewed transaction.
nonisolated enum Authority: Sendable {
    /// A saved account that signs after authentication with its protected recovery.
    case account(Account)
    /// An in-memory one-time account, such as a redeem code's, that signs without authentication.
    case oneTime(OneTimeAccount)

    /// The address whose signature slot this authority fills.
    ///
    /// - Throws: ``ValidationError/invalidAddress`` if a one-time account's address isn't valid,
    ///   which its 32-byte public key prevents.
    var address: Address {
        get throws {
            switch self {
            case .account(let account): account.address
            case .oneTime(let account): try Address(account.address)
            }
        }
    }
}
