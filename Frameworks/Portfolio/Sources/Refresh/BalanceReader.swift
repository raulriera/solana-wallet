import Foundation
import RPC
import Transactions

/// A type that reads a wallet's native SOL and listed token balances from a network source.
protocol BalanceReading: Sendable {
    /// The network queried by the source.
    var network: Network { get }

    /// Reads native SOL and every listed token's balance.
    ///
    /// - Parameters:
    ///   - owner: The wallet address to read.
    ///   - minContextSlot: The earliest acceptable balance observation, or `nil`.
    /// - Returns: A complete snapshot without prices.
    /// - Throws: A cancellation, validation, token-list, or RPC error.
    func snapshot(for owner: String, minContextSlot: UInt64?) async throws -> Snapshot
}

/// Reads an account's balances with one standard RPC request, which every provider supports.
struct BalanceReader: BalanceReading {
    let rpc: any RPC
    let tokenLists: TokenListCoordinator
    var network: Network { rpc.network }

    /// Reads the wallet and each listed token's associated token account at one ledger context.
    ///
    /// - Parameters:
    ///   - owner: The wallet address to read.
    ///   - minContextSlot: The earliest acceptable balance observation, or `nil`.
    /// - Returns: Native SOL followed by the listed tokens, without prices.
    /// - Throws: A cancellation, validation, token-list, or RPC error, or ``AccountReadError`` for an invalid response.
    @concurrent
    func snapshot(for owner: String, minContextSlot: UInt64? = nil) async throws -> Snapshot {
        let list = try await tokenLists.list(for: owner)
        let wallet = try Address(owner)
        let accounts = try list.accounts(of: wallet)
        try Task.checkCancellation()
        let contents = try await rpc.accounts(at: accounts, minContextSlot: minContextSlot)
        // A wallet that was never funded has no account on the ledger, so it holds no SOL.
        let native = Holding(id: .nativeSOL, amount: Amount(units: contents[0]?.lamports ?? 0, decimals: 9),
                             name: "Solana", symbol: "SOL", imageURL: nil, valuation: nil)
        let tokens = list.tokens.indices.map { index in
            let token = list.tokens[index]
            return Holding(id: .asset(token.mint.value),
                           amount: amount(of: token, at: accounts[index + 1], in: contents[index + 1], owner: wallet),
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
    /// - Returns: The exact balance, zero when the token account doesn't exist yet, even at an address that holds SOL,
    ///   or `nil` when the account can't be read or holds something other than the owner's tokens.
    private func amount(of token: ListedToken, at address: Address, in tokenAccount: Account?, owner: Address) -> Amount? {
        let decoded: TokenAccount?
        do {
            decoded = try tokenAccount.flatMap {
                try TokenAccount(associatedAt: address, programOwner: Address($0.owner), data: $0.data)
            }
        } catch {
            // One unreadable token account leaves that balance unknown instead of failing every other balance.
            return nil
        }
        // A token account that doesn't exist yet holds nothing.
        guard let decoded else { return Amount(units: 0, decimals: token.decimals) }
        guard decoded.mint == token.mint, decoded.owner == owner else { return nil }
        return Amount(units: decoded.amount, decimals: token.decimals)
    }
}
