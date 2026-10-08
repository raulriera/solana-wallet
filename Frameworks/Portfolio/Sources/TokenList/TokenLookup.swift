import Foundation
import RPC
import Transactions

/// Looks up a pasted mint address, so a person can check a token before adding it.
struct TokenLookup: Sendable {
    let rpc: any RPC
    let logos: (any LogoProviding)?

    /// Reads a mint and its Metaplex metadata account with one request, then adds the provider's logo.
    ///
    /// - Parameter mint: The pasted mint address.
    /// - Returns: The token with its on-chain name and symbol, and its logo when the provider has one.
    /// - Throws: ``TokenLookupError`` when the address isn't a fungible token mint, or a validation or RPC error.
    @concurrent
    func preview(of mint: Address) async throws -> TokenPreview {
        let accounts = try await rpc.accounts(at: [mint, TokenMetadata.metaplexAccount(for: mint)])
        guard let account = accounts[0], let owner = try? Address(account.owner),
              let tokenMint = try? TokenMint(address: mint, owner: owner, data: account.data) else {
            throw TokenLookupError.notToken
        }
        guard !tokenMint.isNonFungible else { throw TokenLookupError.nonFungible }
        // A Token-2022 mint can keep its metadata itself; other tokens keep it in a Metaplex account.
        var metadata = tokenMint.metadata
        if metadata == nil, let metaplex = accounts[1], let metaplexOwner = try? Address(metaplex.owner) {
            metadata = try? TokenMetadata(metaplexAccount: metaplex.data, owner: metaplexOwner, mint: mint)
        }
        let token = ListedToken(mint: mint, program: tokenMint.program, decimals: tokenMint.decimals,
                                symbol: metadata?.symbol, name: metadata?.name)
        // A logo is decoration: a failed lookup leaves the preview without one.
        let logo = try? await logos?.logos(for: [mint.value])[mint.value]
        try Task.checkCancellation()
        return TokenPreview(token: token, logo: logo)
    }
}
