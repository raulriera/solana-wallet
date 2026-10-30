import RPC
import Wallet

/// A service that finds the accounts of a recovery phrase that hold SOL with one RPC request.
nonisolated struct AccountDiscovery: AccountDiscovering {
    private let wallet: any WalletProviding
    private let rpc: any RPC

    /// Creates an account discovery service.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client that reads the balances.
    ///   - wallet: The service that derives addresses.
    init(rpc: any RPC, wallet: any WalletProviding = Wallet()) {
        self.rpc = rpc
        self.wallet = wallet
    }

    @concurrent
    func discover(for phrase: RecoveryPhrase, passphrase: String) async throws -> [DerivedAccount] {
        try Task.checkCancellation()
        let paths = try (UInt32(0)..<10).flatMap { index in
            [.solana(account: index), try DerivationPath("m/44'/501'/\(index)'")]
        }
        let candidates = try await wallet.accounts(for: phrase, passphrase: passphrase, paths: paths)
        guard candidates.map(\.path) == paths else { throw AccountDiscoveryError.mismatchedAccounts }
        try Task.checkCancellation()
        let native = try await rpc.send(GetMultipleAccounts(addresses: candidates.map(\.address)))
        guard native.value.count == candidates.count else { throw AccountDiscoveryError.mismatchedAccounts }

        let matches = zip(candidates, native.value).compactMap { candidate, account in
            (account?.lamports ?? 0) > 0 ? candidate : nil
        }
        try Task.checkCancellation()
        return matches
    }
}
