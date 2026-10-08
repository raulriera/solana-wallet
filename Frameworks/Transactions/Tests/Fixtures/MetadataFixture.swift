import Foundation
import Testing
import Transactions

/// Public mainnet account bytes for metadata decoding, read with `getMultipleAccounts`.
enum MetadataFixtures {
    /// The USD Coin mint, whose metadata is in a Metaplex account.
    static let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    /// The address of USD Coin's Metaplex metadata account.
    static let usdcMetadataAccount = "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq"
    /// The PayPal USD mint, a Token-2022 mint that keeps its metadata in its own extension.
    static let pyusdMint = "2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo"
    /// The address where PayPal USD would have a Metaplex metadata account; none exists.
    static let pyusdMetadataAccount = "5mf2C8LGCjkWPb4inZNEjyF8WpXQpfNG2pKgsJqy4Rfg"
    /// A collection NFT's mint, with no decimals and a supply of one.
    static let nftMint = "J1S9H3QjnRtBbbuD4HjPV6RpRhwuk4zKbxsnCHuTgh9w"

    /// The USD Coin mint account, encoded in Base64.
    static let usdcMintData = [
        "AQAAAJj+huiNm+Lqi8HMpIeLKYjCQPUrhCS/tA7Rot3LXhmbdQK+gUo+GgAGAQEAAABicKqKWcWUBbRShshncubNEm6bil06OFNt",
        "N/e0FOi2Zw==",
    ].joined()

    /// USD Coin's Metaplex metadata account, encoded in Base64.
    static let usdcMetadataData = [
        "BBzjWe1aAS4E+hQrnHUaHF6Hz9CgFhuchf/TG3jN/Nj2xvp6877brTo9ZfNqq8l0MbG75MLS9uDkfKYCA0UvXWEgAAAAVVNEIENv",
        "aW4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAKAAAAVVNEQwAAAAAAAMgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAfwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAA==",
    ].joined()

    /// The PayPal USD mint account with its extensions, encoded in Base64.
    static let pyusdMintData = [
        "AQAAAJPkMU4Y+uEbsZMeeiiX9ljfNXCarVZ7fbwaCVSmePpU5CRQxqp7AgAGAQEAAAAXhTJh72q4Uypn8FOGWq0xKT/PB88SCrW5",
        "oVcGVI3AKwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAQMAIAAXhTJh72q4Uypn8FOGWq0xKT/PB88SCrW5oVcGVI3AKwwAIAAXhTJh72q4Uypn8FOGWq0xKT/P",
        "B88SCrW5oVcGVI3AKwEAbAAXhTJh72q4Uypn8FOGWq0xKT/PB88SCrW5oVcGVI3AKxeFMmHvarhTKmfwU4ZarTEpP88HzxIKtbmh",
        "VwZUjcArAAAAAAAAAABdAgAAAAAAAAAAAAAAAAAAAABdAgAAAAAAAAAAAAAAAAAAAAAEAEEAF4UyYe9quFMqZ/BThlqtMSk/zwfP",
        "Egq1uaFXBlSNwCsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAIEAF4UyYe9quFMqZ/BThlqtMSk/zwfPEgq1uaFX",
        "BlSNwCscN+ZDO3ME3YJzeuQNm4vzxJ9bDmxJqNUzKLPlBpAcVwEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADgBAABeFMmHvarhTKmfwU4ZarTEpP88HzxIKtbmhVwZUjcArAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAASAEAAF4UyYe9quFMqZ/BThlqtMSk/zwfPEgq1uaFXBlSNwCsXkkg7bIoqh7dHHYFPlZH5OVyE",
        "Cpzj2fTVun06S4p0nhMArgAXhTJh72q4Uypn8FOGWq0xKT/PB88SCrW5oVcGVI3AKxeSSDtsiiqHt0cdgU+Vkfk5XIQKnOPZ9NW6",
        "fTpLinSeCgAAAFBheVBhbCBVU0QFAAAAUFlVU0RPAAAAaHR0cHM6Ly90b2tlbi1tZXRhZGF0YS5wYXhvcy5jb20vcHl1c2RfbWV0",
        "YWRhdGEvcHJvZC9zb2xhbmEvcHl1c2RfbWV0YWRhdGEuanNvbgAAAAA=",
    ].joined()

    /// The collection NFT's mint account, encoded in Base64.
    static let nftMintData = [
        "AQAAABK4Ju63JqUbepW884c9MYvfCDN/CLsI5YAPhTC5C1h7AQAAAAAAAAAAAQEAAAASuCbutyalG3qVvPOHPTGL3wgzfwi7COWA",
        "D4UwuQtYew==",
    ].joined()

    /// Decodes a fixture mint as its token program reports it.
    ///
    /// - Parameters:
    ///   - mint: The mint address.
    ///   - program: The owning token program.
    ///   - data: The mint account's Base64 bytes.
    /// - Returns: The typed mint.
    /// - Throws: A fixture or account decoding error.
    static func mint(_ mint: String, program: TokenProgram, data: String) throws -> TokenMint {
        try TokenMint(address: Address(mint), owner: Address(program.rawValue), data: #require(Data(base64Encoded: data)))
    }
}
