import RPC
import Transactions
import Wallet

/// Positive account observations within an explicit, bounded scan on one network.
///
/// An empty result only means no activity was found in this range using the provider's
/// available state and history. It does not validate a passphrase or establish non-use.
nonisolated struct Discovery: Sendable {
    /// The network queried by the discovery coordinator.
    let network: Network
    /// The account indices scanned in both supported path families.
    let indices: Range<UInt32>
    /// Accounts in index order, with the change family preceding the account family.
    let accounts: [Match]

    /// The next bounded range, which callers must explicitly request to continue.
    var nextIndices: Range<UInt32>? {
        guard indices.upperBound < 0x8000_0000 else { return nil }
        return indices.upperBound..<min(indices.upperBound + 20, 0x8000_0000)
    }

    /// One account's exact recovery path and the first positive observation found.
    struct Match: Sendable {
        let account: DerivedAccount
        let evidence: Evidence

        /// Pairs a locally derived account with positive network evidence.
        /// - Parameters:
        ///   - account: The public address and exact derivation path.
        ///   - evidence: The first sufficient observation; not an exhaustive account inventory.
        init(account: DerivedAccount, evidence: Evidence) {
            self.account = account
            self.evidence = evidence
        }
    }

    /// A sufficient discovery signal; token ownership also includes empty token accounts.
    enum Evidence: Sendable, Equatable {
        case solBalance
        case tokenAccount(TokenProgram)
        case transactionHistory
    }

    /// Creates a completed scan without retaining recovery material.
    /// - Parameters:
    ///   - network: The queried network.
    ///   - indices: The scanned indices in both families.
    ///   - accounts: Positive observations in derivation order.
    init(network: Network, indices: Range<UInt32>, accounts: [Match]) {
        self.network = network
        self.indices = indices
        self.accounts = accounts
    }
}
