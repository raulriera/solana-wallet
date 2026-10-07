import Foundation
import RPC
import Transactions

/// A type that reads a wallet's native SOL and listed token balances from a network source.
protocol BalanceReading: Sendable {
    /// The network queried by the source.
    var network: Network { get }

    /// Reads native SOL and every listed token's balance.
    ///
    /// - Parameter owner: The wallet address to read.
    /// - Returns: A complete snapshot without prices.
    /// - Throws: A cancellation, validation, token-list, or RPC error.
    func snapshot(for owner: String) async throws -> Snapshot
}

/// Reads an account's balances with one standard RPC request, which every provider supports.
struct BalanceReader: BalanceReading {
    let rpc: any RPC
    let tokenLists: TokenListCoordinator
    var network: Network { rpc.network }

    /// Reads the wallet and each listed token's associated token account at one ledger context.
    ///
    /// - Parameter owner: The wallet address to read.
    /// - Returns: Native SOL followed by the listed tokens, without prices.
    /// - Throws: A cancellation, validation, token-list, or RPC error, or ``BalanceError`` for a mismatched response.
    @concurrent
    func snapshot(for owner: String) async throws -> Snapshot {
        let list = try await tokenLists.list(for: owner)
        let wallet = try Address(owner)
        let tokenAccounts = try list.tokens.map { try $0.program.associatedAccount(owner: wallet, mint: $0.mint) }
        try Task.checkCancellation()
        let response = try await rpc.send(GetMultipleAccounts(addresses: [owner] + tokenAccounts.map(\.value)))
        guard response.value.count == tokenAccounts.count + 1 else { throw BalanceError.mismatchedResponse }
        // A wallet that was never funded has no account on the ledger, so it holds no SOL.
        let native = Holding(id: .nativeSOL, amount: Amount(units: response.value[0]?.lamports ?? 0, decimals: 9),
                             name: "Solana", symbol: "SOL", imageURL: nil, valuation: nil)
        let tokens = list.tokens.indices.map { index in
            let token = list.tokens[index]
            return Holding(id: .asset(token.mint.value),
                           amount: amount(of: token, at: tokenAccounts[index], in: response.value[index + 1], owner: wallet),
                           name: token.name, symbol: token.symbol, imageURL: nil, valuation: nil)
        }
        try Task.checkCancellation()
        return Snapshot(owner: owner, network: network, holdings: [native] + tokens, fetchedAt: Date())
    }

    /// Reads a listed token's balance from its associated token account.
    ///
    /// - Parameters:
    ///   - token: The listed token.
    ///   - address: The token's associated token account address.
    ///   - tokenAccount: The account's contents, or `nil` if it doesn't exist.
    ///   - owner: The wallet that must own the token account.
    /// - Returns: The exact balance, zero when the token account doesn't exist,
    ///   or `nil` when it holds something other than the owner's tokens.
    private func amount(of token: ListedToken, at address: Address, in tokenAccount: Account?, owner: Address) -> Amount? {
        // A token account that doesn't exist holds nothing.
        guard let tokenAccount else { return Amount(units: 0, decimals: token.decimals) }
        // One unreadable token account leaves that balance unknown instead of failing every other balance.
        guard let program = try? Address(tokenAccount.owner),
              let decoded = try? TokenAccount(address: address, programOwner: program, data: tokenAccount.data),
              decoded.mint == token.mint, decoded.owner == owner else { return nil }
        return Amount(units: decoded.amount, decimals: token.decimals)
    }
}

/// A failure that prevents a complete balance read.
enum BalanceError: Error {
    /// The provider returned a different number of accounts than the request asked for.
    case mismatchedResponse
}
