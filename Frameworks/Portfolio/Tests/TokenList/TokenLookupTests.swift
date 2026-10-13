import Foundation
import Portfolio
import RPC
import Testing
@testable import Transactions

/// Verifies looking up a pasted mint address with real RPC clients and recorded accounts.
struct TokenLookupTests {
    /// The kinds of address that can't become a listed token.
    enum Refusal: CaseIterable {
        /// No account exists at the address.
        case missing
        /// The address is a wallet.
        case wallet
        /// The address is a token account, not a mint.
        case tokenAccount
        /// The mint describes an NFT.
        case nft
    }

    /// Verifies one request reads the mint and its Metaplex account, and the token gets its on-chain name and symbol.
    @Test
    func `A pasted mint shows its on-chain name and symbol`() async throws {
        let mint = try Address(usdcMint)
        let metadataAccount = try TokenMetadata.metaplexAccount(for: mint)
        let http = LookupResponses(accounts: [
            usdcMint: mintAccount(decimals: 6, supply: 1_000),
            metadataAccount.value: Account(owner: metaplexProgram, lamports: 1, executable: false,
                                           data: metaplexData(mint: mint, name: "USD Coin", symbol: "USDC")),
        ])

        let preview = try await Portfolio(rpc: http.client).token(at: mint)

        #expect(preview == TokenPreview(token: ListedToken(mint: mint, program: .token, decimals: 6,
                                                           symbol: "USDC", name: "USD Coin"), logo: nil))
        #expect(await http.requests == [[usdcMint, metadataAccount.value]])
    }

    /// Verifies a token without on-chain metadata has no name or symbol, rather than failing the lookup.
    @Test
    func `A mint without metadata has no name or symbol`() async throws {
        let mint = try Address(usdcMint)
        let http = LookupResponses(accounts: [usdcMint: mintAccount(decimals: 6, supply: 1_000)])

        let preview = try await Portfolio(rpc: http.client).token(at: mint)

        #expect(preview.token == ListedToken(mint: mint, program: .token, decimals: 6, symbol: nil, name: nil))
    }

    /// Verifies addresses that aren't fungible token mints are refused before they can reach a list, including while a
    /// provider with logo copies looks up the address's logo.
    /// - Parameters:
    ///   - refusal: The kind of address pasted.
    ///   - helius: Whether the provider also looks up logos.
    @Test(arguments: Refusal.allCases, [false, true])
    func `Addresses that aren't fungible token mints are refused`(_ refusal: Refusal, helius: Bool) async throws {
        let mint = try Address(usdcMint)
        let account: Account? = switch refusal {
        case .missing: nil
        case .wallet: Account(owner: "11111111111111111111111111111111", lamports: 1, executable: false, data: Data())
        case .tokenAccount:
            Account(owner: TokenProgram.token.rawValue, lamports: 1, executable: false,
                    data: tokenAccountData(mint: mint, owner: try Address(testWallet), units: 5, program: .token))
        case .nft: mintAccount(decimals: 0, supply: 1)
        }
        let http = LookupResponses(accounts: account.map { [usdcMint: $0] } ?? [:])

        let rpc: any RPC = helius ? http.heliusClient : http.client

        await #expect(throws: refusal == .nft ? TokenLookupError.nonFungible : .notToken) {
            try await Portfolio(rpc: rpc).token(at: mint)
        }
    }

    /// Verifies a provider with logo copies adds the logo, and a failed logo lookup leaves only the logo out.
    /// - Parameter logoFails: Whether the logo lookup fails.
    @Test(arguments: [false, true])
    func `A provider with logo copies adds the logo to the preview`(logoFails: Bool) async throws {
        let mint = try Address(usdcMint)
        let http = LookupResponses(accounts: [usdcMint: mintAccount(decimals: 6, supply: 1_000)]) { _ in
            if logoFails { throw URLError(.notConnectedToInternet) }
            return [usdcMint: "https://cdn.example.com/usdc.png"]
        }

        let preview = try await Portfolio(rpc: http.heliusClient).token(at: mint)

        #expect(preview.logo == (logoFails ? nil : URL(string: "https://cdn.example.com/usdc.png")))
        #expect(preview.token.decimals == 6)
        #expect(await http.logoRequests == [[usdcMint]])
    }
}

/// The Metaplex Token Metadata program, which owns metadata accounts.
private let metaplexProgram = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"

/// Creates an initialized SPL Token mint account without mint or freeze authorities.
/// - Parameters:
///   - decimals: The mint's decimal places.
///   - supply: The number of base units in circulation.
/// - Returns: The mint account as the token program stores it.
private func mintAccount(decimals: UInt8, supply: UInt64) -> Account {
    var bytes = [UInt8](repeating: 0, count: 36) // No mint authority.
    bytes += withUnsafeBytes(of: supply.littleEndian, Array.init)
    bytes += [decimals, 1] // Initialized.
    bytes += [UInt8](repeating: 0, count: 36) // No freeze authority.
    return Account(owner: TokenProgram.token.rawValue, lamports: 1_461_600, executable: false, data: Data(bytes))
}

/// Encodes a version 1 Metaplex metadata account for a mint.
/// - Parameters:
///   - mint: The mint the metadata describes.
///   - name: The token's name.
///   - symbol: The token's symbol.
/// - Returns: The account bytes, with the name and symbol padded as Metaplex stores them.
private func metaplexData(mint: Address, name: String, symbol: String) -> Data {
    /// Encodes text as a length-prefixed string padded with zero bytes.
    func padded(_ text: String, to length: Int) -> [UInt8] {
        let bytes = Array(text.utf8) + [UInt8](repeating: 0, count: length - text.utf8.count)
        return withUnsafeBytes(of: UInt32(length).littleEndian, Array.init) + bytes
    }
    return Data([4] + [UInt8](repeating: 0, count: 32) + mint.bytes + padded(name, to: 32) + padded(symbol, to: 10))
}
