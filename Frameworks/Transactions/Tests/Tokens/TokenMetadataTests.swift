import Foundation
import Testing
import Transactions

/// Checks reading token names and symbols from real mainnet metadata.
struct TokenMetadataTests {
    /// The ways a Metaplex account can fail to describe the requested mint.
    enum Mismatch: CaseIterable {
        /// The account belongs to another program.
        case owner
        /// The account describes another mint.
        case mint
        /// The account ends inside the name.
        case truncated
    }

    /// Verifies the derived address is the account that holds a mint's metadata on mainnet.
    @Test
    func `Metaplex metadata accounts derive from the mint`() throws {
        #expect(try TokenMetadata.metaplexAccount(for: Address(MetadataFixtures.usdcMint)).value
                == MetadataFixtures.usdcMetadataAccount)
        #expect(try TokenMetadata.metaplexAccount(for: Address(MetadataFixtures.pyusdMint)).value
                == MetadataFixtures.pyusdMetadataAccount)
    }

    /// Verifies a Metaplex account supplies the name and symbol without their padding.
    @Test
    func `A Metaplex account supplies the name and symbol`() throws {
        let metadata = try TokenMetadata(metaplexAccount: #require(Data(base64Encoded: MetadataFixtures.usdcMetadataData)),
                                         owner: Address(metaplexProgram), mint: Address(MetadataFixtures.usdcMint))

        #expect(metadata.name == "USD Coin")
        #expect(metadata.symbol == "USDC")
    }

    /// Verifies a Metaplex account is read only when it belongs to the Metaplex program and describes the mint.
    /// - Parameter mismatch: How the account fails to describe the mint.
    @Test(arguments: Mismatch.allCases)
    func `A Metaplex account must belong to the program and describe the mint`(_ mismatch: Mismatch) throws {
        let data = try #require(Data(base64Encoded: MetadataFixtures.usdcMetadataData))
        let owner = try Address(mismatch == .owner ? TokenProgram.token.rawValue : metaplexProgram)
        let mint = try Address(mismatch == .mint ? MetadataFixtures.pyusdMint : MetadataFixtures.usdcMint)

        #expect(throws: TokenError.invalidAccount) {
            try TokenMetadata(metaplexAccount: mismatch == .truncated ? data.prefix(70) : data, owner: owner, mint: mint)
        }
    }

    /// Verifies a Token-2022 mint reads its own metadata extension, and a mint without one has none.
    @Test
    func `A Token-2022 mint supplies its own name and symbol`() throws {
        let pyusd = try MetadataFixtures.mint(MetadataFixtures.pyusdMint, program: .token2022,
                                              data: MetadataFixtures.pyusdMintData)
        let usdc = try MetadataFixtures.mint(MetadataFixtures.usdcMint, program: .token, data: MetadataFixtures.usdcMintData)

        #expect(pyusd.metadata?.name == "PayPal USD")
        #expect(pyusd.metadata?.symbol == "PYUSD")
        #expect(usdc.metadata == nil)
    }

    /// Verifies only a mint with no decimals and a supply of one counts as an NFT.
    @Test
    func `Only a mint with no decimals and a supply of one is non-fungible`() throws {
        let nft = try MetadataFixtures.mint(MetadataFixtures.nftMint, program: .token, data: MetadataFixtures.nftMintData)
        let usdc = try MetadataFixtures.mint(MetadataFixtures.usdcMint, program: .token, data: MetadataFixtures.usdcMintData)

        #expect(nft.isNonFungible)
        #expect(!usdc.isNonFungible)
    }
}

/// The Metaplex Token Metadata program, which owns metadata accounts.
private let metaplexProgram = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"
