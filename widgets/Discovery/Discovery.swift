import RPC
import Wallet

/// SOL-funded accounts within an explicit, bounded scan on one network.
///
/// An empty result means no positive SOL balances were found in this range.
/// Zero-SOL accounts are intentionally excluded even if they own tokens or have history.
nonisolated struct Discovery: Sendable {
    /// Ten indices in each of the two path families, for at most twenty addresses per scan.
    static let indicesPerScan: UInt32 = 10

    /// The network queried by the discovery coordinator.
    let network: Network
    /// The account indices scanned in both supported path families.
    let indices: Range<UInt32>
    /// Accounts in index order, with the change family preceding the account family.
    let accounts: [DerivedAccount]

    /// The next bounded range, which callers must explicitly request to continue.
    var nextIndices: Range<UInt32>? {
        guard indices.upperBound < 0x8000_0000 else { return nil }
        return indices.upperBound..<min(indices.upperBound + Self.indicesPerScan, 0x8000_0000)
    }

    /// Creates a completed scan without retaining recovery material.
    /// - Parameters:
    ///   - network: The queried network.
    ///   - indices: The scanned indices in both families.
    ///   - accounts: SOL-funded accounts in derivation order.
    init(network: Network, indices: Range<UInt32>, accounts: [DerivedAccount]) {
        self.network = network
        self.indices = indices
        self.accounts = accounts
    }
}
