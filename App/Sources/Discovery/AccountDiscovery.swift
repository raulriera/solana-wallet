import RPC
import Wallet

/// Discovers SOL-funded accounts with one RPC request and no retained recovery material.
nonisolated struct AccountDiscovery: AccountDiscovering {
    /// A scan cannot be completed with the supplied range or provider response.
    enum Failure: Error, Equatable {
        case invalidRange
        case mismatchedAccounts
    }

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

    /// Scans every requested index, including gaps, without automatically expanding the range.
    ///
    /// Candidates use `m/44'/501'/i'/0'` and `m/44'/501'/i'`. One combined account
    /// read returns their SOL balances. Zero-SOL and missing accounts are ignored,
    /// including accounts with tokens or previous activity. Only public addresses reach RPC.
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - indices: One through ten account indices below 2³¹.
    /// - Returns: SOL-funded accounts in the completed range on the selected network.
    /// - Throws: A validation, derivation, RPC, or cancellation error; no partial success is returned.
    @concurrent
    func discover(for phrase: RecoveryPhrase, passphrase: String, indices: Range<UInt32>) async throws -> Discovery {
        try Task.checkCancellation()
        guard !indices.isEmpty, indices.upperBound <= 0x8000_0000,
              indices.upperBound - indices.lowerBound <= Discovery.indicesPerScan else { throw Failure.invalidRange }
        let paths = try indices.flatMap { index in
            try [DerivationPath("m/44'/501'/\(index)'/0'"), DerivationPath("m/44'/501'/\(index)'")]
        }
        let candidates = try await wallet.accounts(for: phrase, passphrase: passphrase, paths: paths)
        guard candidates.map(\.path) == paths else { throw Failure.mismatchedAccounts }
        try Task.checkCancellation()
        let native = try await rpc.send(GetMultipleAccounts(addresses: candidates.map(\.address)))
        guard native.value.count == candidates.count else { throw Failure.mismatchedAccounts }

        let matches = zip(candidates, native.value).compactMap { candidate, account in
            (account?.lamports ?? 0) > 0 ? candidate : nil
        }
        try Task.checkCancellation()
        return Discovery(network: rpc.network, indices: indices, accounts: matches)
    }
}
