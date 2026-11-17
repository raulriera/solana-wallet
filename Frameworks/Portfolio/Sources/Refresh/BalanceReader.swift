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
        let native = Holding(asset: .nativeSOL, balance: TokenAmount(lamports: contents[0]?.lamports ?? 0),
                             imageURL: nil, valuation: nil)
        let tokens = list.mints.indices.map { index in
            let mint = list.mints[index]
            let account = balance(of: mint, at: accounts[index + 1], in: contents[index + 1], owner: wallet)
            return Holding(asset: .token(mint), balance: account.balance, otherOwner: account.otherOwner, imageURL: nil,
                           valuation: nil)
        }
        try Task.checkCancellation()
        return Snapshot(owner: owner, network: network, holdings: [native] + tokens)
    }

    /// Reads a listed token's balance from its associated token account.
    ///
    /// - Parameters:
    ///   - mint: The listed token's mint.
    ///   - address: The token's associated token account address.
    ///   - tokenAccount: The account's contents, or `nil` if it doesn't exist.
    ///   - owner: The wallet that must own the token account.
    /// - Returns: The balance, or `nil` if unknown, and the token account's owner if it isn't the wallet.
    private func balance(of mint: Mint, at address: Address, in tokenAccount: Account?,
                         owner: Address) -> (balance: TokenAmount?, otherOwner: Address?) {
        let decoded: Token?
        do {
            decoded = try tokenAccount.flatMap {
                try Token(associatedAt: address, programAddress: Address($0.owner), data: $0.data)
            }
        } catch {
            return (nil, nil)
        }
        guard let decoded else { return (TokenAmount(amount: 0, decimals: mint.decimals), nil) }
        guard decoded.mint == mint.address else { return (nil, nil) }
        guard decoded.owner == owner else { return (nil, decoded.owner) }
        return (TokenAmount(amount: decoded.amount, decimals: mint.decimals), nil)
    }
}

extension TokenList {
    /// The identities of native SOL and each listed token, in order.
    var holdingIDs: [Asset.ID] {
        [.nativeSOL] + mints.map { .token(mint: $0.address) }
    }
}
