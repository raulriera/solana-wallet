import Foundation
import Testing
import Transactions

struct TokenMetadataTests {
    enum Mismatch: CaseIterable {
        case owner
        case mint
        case truncated
    }

    @Test
    func `Metaplex metadata accounts derive from the mint`() throws {
        #expect(try TokenMetadata.metaplexAccount(for: Address(MetadataFixtures.usdcMint)).value
                == MetadataFixtures.usdcMetadataAccount)
        #expect(try TokenMetadata.metaplexAccount(for: Address(MetadataFixtures.pyusdMint)).value
                == MetadataFixtures.pyusdMetadataAccount)
    }

    @Test
    func `A Metaplex account supplies the name and symbol`() throws {
        let metadata = try TokenMetadata(metaplexAccount: #require(Data(base64Encoded: MetadataFixtures.usdcMetadataData)),
                                         owner: Address(metaplexProgram), mint: Address(MetadataFixtures.usdcMint))

        #expect(metadata.name == "USD Coin")
        #expect(metadata.symbol == "USDC")
    }

    @Test(arguments: Mismatch.allCases)
    func `A Metaplex account must belong to the program and describe the mint`(_ mismatch: Mismatch) throws {
        let data = try #require(Data(base64Encoded: MetadataFixtures.usdcMetadataData))
        let owner = try Address(mismatch == .owner ? TokenProgram.token.rawValue : metaplexProgram)
        let mint = try Address(mismatch == .mint ? MetadataFixtures.pyusdMint : MetadataFixtures.usdcMint)

        #expect(throws: TokenError.invalidAccount) {
            try TokenMetadata(metaplexAccount: mismatch == .truncated ? data.prefix(70) : data, owner: owner, mint: mint)
        }
    }

    @Test
    func `A Token-2022 mint supplies its own name and symbol`() throws {
        let pyusd = try MetadataFixtures.mint(MetadataFixtures.pyusdMint, program: .token2022,
                                              data: MetadataFixtures.pyusdMintData)
        let usdc = try MetadataFixtures.mint(MetadataFixtures.usdcMint, program: .token, data: MetadataFixtures.usdcMintData)

        #expect(pyusd.metadata?.name == "PayPal USD")
        #expect(pyusd.metadata?.symbol == "PYUSD")
        #expect(usdc.metadata == nil)
    }

    @Test
    func `A saved mint keeps its facts and not its account data`() throws {
        let pyusd = try MetadataFixtures.mint(MetadataFixtures.pyusdMint, program: .token2022,
                                              data: MetadataFixtures.pyusdMintData)

        let saved = try JSONDecoder().decode(Mint.self, from: JSONEncoder().encode(pyusd))

        #expect(saved == Mint(address: pyusd.address, program: .token2022, decimals: pyusd.decimals,
                              metadata: TokenMetadata(name: "PayPal USD", symbol: "PYUSD")))
        #expect(throws: TokenError.invalidAccount) { try saved.associatedAccountSize }
        #expect(throws: TokenError.invalidAccount) { try saved.isNonFungible }
    }

    @Test
    func `Only a mint with no decimals and a supply of one is non-fungible`() throws {
        let nft = try MetadataFixtures.mint(MetadataFixtures.nftMint, program: .token, data: MetadataFixtures.nftMintData)
        let usdc = try MetadataFixtures.mint(MetadataFixtures.usdcMint, program: .token, data: MetadataFixtures.usdcMintData)

        #expect(try nft.isNonFungible)
        #expect(try !usdc.isNonFungible)
    }
}

private let metaplexProgram = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"
