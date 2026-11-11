import Foundation
import RPC
import Transactions

/// A service that looks up tokens by their mint addresses.
struct TokenLookup: Sendable {
    let rpc: any RPC
    let logos: (any LogoProviding)?

    /// Looks up a token and its logo by mint address.
    ///
    /// - Parameter mint: The mint address.
    /// - Returns: The token and its logo.
    /// - Throws: ``TokenLookupError`` when the address isn't a fungible token mint, or a validation or RPC error.
    @concurrent
    func preview(of mint: Address) async throws -> TokenPreview {
        async let logoLookup = logos?.logos(for: [mint.value])
        let accounts = try await rpc.accounts(at: [mint.value, TokenMetadata.metaplexAccount(for: mint).value]).value
        guard let account = accounts[0], let owner = try? Address(account.owner),
              let tokenMint = try? TokenMint(address: mint, owner: owner, data: account.data) else {
            throw TokenLookupError.notToken
        }
        guard !tokenMint.isNonFungible else { throw TokenLookupError.nonFungible }
        var metadata = tokenMint.metadata
        if metadata == nil, let metaplex = accounts[1], let metaplexOwner = try? Address(metaplex.owner) {
            metadata = try? TokenMetadata(metaplexAccount: metaplex.data, owner: metaplexOwner, mint: mint)
        }
        let token = ListedToken(mint: mint, program: tokenMint.program, decimals: tokenMint.decimals,
                                symbol: metadata?.symbol, name: metadata?.name)
        let logo = (try? await logoLookup)?[mint.value]
        try Task.checkCancellation()
        return TokenPreview(token: token, logo: logo)
    }
}
