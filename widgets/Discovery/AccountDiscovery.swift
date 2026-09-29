import RPC
import Transactions
import Wallet

/// Discovers account activity without retaining recovery material, writing storage, or touching UI.
nonisolated struct AccountDiscovery: AccountDiscovering {
    /// A scan cannot be completed with the supplied range or provider response.
    enum Failure: Error, Equatable {
        case invalidRange
        case mismatchedAccounts
        case unexpectedTokenProgram
    }

    private let wallet: any WalletProviding
    private let rpc: any RPC

    /// Creates a discovery coordinator using the selected network's ordinary RPC client.
    /// - Parameters:
    ///   - rpc: The provider whose network and available history define the scan.
    ///   - wallet: The service performing local derivation.
    init(rpc: any RPC, wallet: any WalletProviding = Wallet()) {
        self.rpc = rpc
        self.wallet = wallet
    }

    /// Scans every requested index, including gaps, without automatically expanding the range.
    ///
    /// Candidates use `m/44'/501'/i'/0'` and `m/44'/501'/i'`. Reads are sequential
    /// and single-attempt; rate limits propagate to the caller without retries or delays.
    /// Only public addresses reach RPC. Each account stops at its first positive signal.
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - indices: One through twenty account indices below 2³¹.
    /// - Returns: All positive observations in the completed range on the selected network.
    /// - Throws: A validation, derivation, RPC, or cancellation error; no partial success is returned.
    @concurrent
    func discover(for phrase: RecoveryPhrase, passphrase: String, indices: Range<UInt32>) async throws -> Discovery {
        try Task.checkCancellation()
        guard !indices.isEmpty, indices.upperBound <= 0x8000_0000,
              indices.upperBound - indices.lowerBound <= 20 else { throw Failure.invalidRange }
        let paths = try indices.flatMap { index in
            try [DerivationPath("m/44'/501'/\(index)'/0'"), DerivationPath("m/44'/501'/\(index)'")]
        }
        let candidates = try await wallet.accounts(for: phrase, passphrase: passphrase, paths: paths)
        guard candidates.map(\.path) == paths else { throw Failure.mismatchedAccounts }
        try Task.checkCancellation()
        let native = try await rpc.send(GetMultipleAccounts(addresses: candidates.map(\.address)))
        guard native.value.count == candidates.count else { throw Failure.mismatchedAccounts }

        var matches: [Discovery.Match] = []
        for (candidate, account) in zip(candidates, native.value) {
            try Task.checkCancellation()
            let evidence: Discovery.Evidence?
            if (account?.lamports ?? 0) > 0 {
                evidence = .solBalance
            } else {
                evidence = try await activity(for: candidate.address, minimumSlot: native.context.slot)
            }
            if let evidence { matches.append(.init(account: candidate, evidence: evidence)) }
        }
        try Task.checkCancellation()
        return Discovery(network: rpc.network, indices: indices, accounts: matches)
    }

    /// Checks token ownership in both programs, then available address history.
    /// - Parameters:
    ///   - address: The locally derived public address.
    ///   - minimumSlot: The earliest node context accepted after the native-account read.
    /// - Returns: The first positive observation, or `nil` if none was available.
    /// - Throws: An RPC, response-validation, or cancellation error.
    private func activity(for address: String, minimumSlot: UInt64) async throws -> Discovery.Evidence? {
        for program in TokenProgram.allCases {
            try Task.checkCancellation()
            let tokens = try await rpc.send(GetTokenAccountsByOwner(
                owner: address, program: program.rawValue, minContextSlot: minimumSlot))
            guard tokens.value.allSatisfy({ $0.account.owner == program.rawValue }) else {
                throw Failure.unexpectedTokenProgram
            }
            if !tokens.value.isEmpty { return .tokenAccount(program) }
        }
        try Task.checkCancellation()
        let history = try await rpc.send(GetSignaturesForAddress(address: address, minContextSlot: minimumSlot))
        return history.isEmpty ? nil : .transactionHistory
    }
}
