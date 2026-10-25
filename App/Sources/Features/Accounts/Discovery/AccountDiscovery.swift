import RPC
import Wallet

/// Discovers SOL-funded accounts with one RPC request and no retained recovery material.
nonisolated struct AccountDiscovery: AccountDiscovering {
    private let wallet: any WalletProviding
    private let rpc: any RPC

    /// Creates a discovery coordinator using the selected network's ordinary RPC client.
    /// - Parameters:
    ///   - rpc: The provider whose network defines the scan.
    ///   - wallet: The service performing local derivation.
    init(rpc: any RPC, wallet: any WalletProviding = Wallet()) {
        self.rpc = rpc
        self.wallet = wallet
    }

    /// Scans indices zero through nine, including gaps, without expanding the range.
    ///
    /// Candidates use `m/44'/501'/i'/0'` and `m/44'/501'/i'`. One combined account
    /// read returns their SOL balances. Zero-SOL and missing accounts are ignored,
    /// including accounts with tokens or previous activity. Only public addresses reach RPC.
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - passphrase: The original BIP-39 passphrase.
    /// - Returns: SOL-funded accounts in derivation order on the selected network.
    /// - Throws: A derivation, RPC, response-validation, or cancellation error; no partial success is returned.
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
