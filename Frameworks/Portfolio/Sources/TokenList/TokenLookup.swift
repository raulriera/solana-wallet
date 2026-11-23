import Foundation
import RPC
import Transactions

/// A service that looks up tokens by their mint addresses.
struct TokenLookup: Sendable {
    let rpc: any LogoProviding

    /// Looks up a token and its logo by mint address.
    ///
    /// - Parameter mint: The mint address.
    /// - Returns: The token's mint and its logo.
    /// - Throws: ``TokenLookupError`` when the address isn't a fungible token mint, or a validation or RPC error.
    @concurrent
    func preview(of mint: Address) async throws -> TokenPreview {
        async let logoLookup = rpc.logos(for: [mint.value])
        let accounts = try await rpc.accounts(at: [mint.value, TokenMetadata.metaplexAccount(for: mint).value]).value
        guard let account = accounts[0], let owner = try? Address(account.owner),
              var decoded = try? Mint(address: mint, programAddress: owner, data: account.data) else {
            throw TokenLookupError.notToken
        }
        guard try !decoded.isNonFungible else { throw TokenLookupError.nonFungible }
        if decoded.metadata == nil, let metaplex = accounts[1], let metaplexOwner = try? Address(metaplex.owner) {
            decoded.metadata = try? TokenMetadata(metaplexAccount: metaplex.data, owner: metaplexOwner, mint: mint)
        }
        let logo = (try? await logoLookup)?[mint.value]
        try Task.checkCancellation()
        return TokenPreview(mint: decoded, logo: logo)
    }
}
