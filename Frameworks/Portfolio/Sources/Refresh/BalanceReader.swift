import Foundation
import RPC
import Transactions

/// A balance reader that reads an account's balances with one standard RPC request.
struct BalanceReader {
    let rpc: any RPC
    var network: Network { rpc.network }

    /// Reads native SOL and the balance of every token in the account's list.
    ///
    /// - Parameters:
    ///   - list: The account's token list.
    ///   - owner: The wallet address.
    ///   - minContextSlot: The earliest slot the response may come from, or `nil` for any slot.
    /// - Returns: A snapshot without prices, with holdings in ``TokenList/holdingIDs`` order.
    /// - Throws: A cancellation, validation, or RPC error.
    @concurrent
    func snapshot(of list: TokenList, for owner: String, minContextSlot: UInt64?) async throws -> Snapshot {
        let wallet = try Address(owner)
        let accounts = try list.accounts(of: wallet)
        try Task.checkCancellation()
        let contents = try await rpc.accounts(at: accounts.map(\.value), minContextSlot: minContextSlot).value
        let native = Holding(id: .nativeSOL, amount: Amount(units: contents[0]?.lamports ?? 0, decimals: 9),
                             name: "Solana", symbol: "SOL", imageURL: nil, valuation: nil)
        let tokens = list.tokens.indices.map { index in
            let token = list.tokens[index]
            let account = balance(of: token, at: accounts[index + 1], in: contents[index + 1], owner: wallet)
            return Holding(id: .asset(token.mint.value), amount: account.amount, otherOwner: account.otherOwner,
                           name: token.name, symbol: token.symbol, imageURL: nil, valuation: nil)
        }
        try Task.checkCancellation()
        return Snapshot(owner: owner, network: network, holdings: [native] + tokens)
    }

    /// Reads a listed token's balance from its associated token account.
    ///
    /// - Parameters:
    ///   - token: The listed token.
    ///   - address: The token's associated token account address.
    ///   - tokenAccount: The account's contents, or `nil` if it doesn't exist.
    ///   - owner: The wallet that must own the token account.
    /// - Returns: The balance, or `nil` if unknown, and the token account's owner if it isn't the wallet.
    private func balance(of token: ListedToken, at address: Address, in tokenAccount: Account?,
                         owner: Address) -> (amount: Amount?, otherOwner: Address?) {
        let decoded: TokenAccount?
        do {
            decoded = try tokenAccount.flatMap {
                try TokenAccount(associatedAt: address, programOwner: Address($0.owner), data: $0.data)
            }
        } catch {
            return (nil, nil)
        }
        guard let decoded else { return (Amount(units: 0, decimals: token.decimals), nil) }
        guard decoded.mint == token.mint else { return (nil, nil) }
        guard decoded.owner == owner else { return (nil, decoded.owner) }
        return (Amount(units: decoded.amount, decimals: token.decimals), nil)
    }
}

extension TokenList {
    /// The identities of native SOL and each listed token, in order.
    var holdingIDs: [Holding.Identity] {
        [.nativeSOL] + tokens.map { .asset($0.mint.value) }
    }
}
