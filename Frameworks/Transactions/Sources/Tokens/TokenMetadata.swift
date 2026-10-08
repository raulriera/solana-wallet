public import Foundation

/// A token's display name and ticker symbol, read from its on-chain metadata.
///
/// Anyone can create a token with any name, so the name alone doesn't identify a token.
public struct TokenMetadata: Sendable, Equatable {
    /// The display name, or `nil` when the metadata has none.
    public let name: String?
    /// The ticker symbol, or `nil` when the metadata has none.
    public let symbol: String?

    /// The Metaplex Token Metadata program, which keeps the metadata of most SPL tokens.
    private static let metaplexProgram = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"

    /// Derives the address of a mint's Metaplex metadata account, which exists only for tokens that have one.
    ///
    /// - Parameter mint: The token's mint address.
    /// - Returns: The metadata account address to read.
    /// - Throws: ``TokenError/addressDerivationFailed`` if no valid bump exists.
    public static func metaplexAccount(for mint: Address) throws -> Address {
        let program = try Address(metaplexProgram)
        return try ProgramAddress.find(seeds: [Array("metadata".utf8), program.bytes, mint.bytes], program: program)
    }

    /// Reads the name and symbol from a mint's Metaplex metadata account.
    ///
    /// - Parameters:
    ///   - data: The account's raw bytes.
    ///   - owner: The account's program owner, which must be the Metaplex program.
    ///   - mint: The mint that the account must describe.
    /// - Throws: ``TokenError/invalidAccount`` for another owner, kind of account, or mint, or for malformed fields.
    public init(metaplexAccount data: Data, owner: Address, mint: Address) throws {
        let bytes = Array(data)
        // Version 1 metadata starts with key 4, then the update authority and the mint.
        guard owner.value == Self.metaplexProgram, bytes.first == 4, bytes.count >= 65,
              Array(bytes[33..<65]) == mint.bytes else { throw TokenError.invalidAccount }
        try self.init(fields: bytes, at: 65)
    }

    /// Reads the name and symbol from a Token-2022 metadata extension.
    ///
    /// - Parameters:
    ///   - bytes: The extension's value.
    ///   - mint: The mint that the extension must describe.
    /// - Throws: ``TokenError/invalidAccount`` for another mint or malformed fields.
    init(metadataExtension bytes: [UInt8], mint: Address) throws {
        // The extension starts with the update authority and the mint.
        guard bytes.count >= 64, Array(bytes[32..<64]) == mint.bytes else { throw TokenError.invalidAccount }
        try self.init(fields: bytes, at: 64)
    }

    /// Reads the name and the symbol, which both formats store as consecutive length-prefixed strings.
    ///
    /// Padding and surrounding whitespace are removed. Empty text or text that isn't UTF-8 is unknown.
    /// - Parameters:
    ///   - bytes: The metadata's bytes.
    ///   - offset: The position of the name's length.
    /// - Throws: ``TokenError/invalidAccount`` if a string runs past the end of the bytes.
    private init(fields bytes: [UInt8], at offset: Int) throws {
        var offset = offset
        /// Reads the string at the current position and moves past it.
        /// - Returns: The trimmed text, or `nil` when it's empty or isn't UTF-8.
        /// - Throws: ``TokenError/invalidAccount`` if the string runs past the end of the bytes.
        func text() throws -> String? {
            let length: UInt32 = try TokenData.integer(bytes, at: offset)
            offset += 4
            guard Int(length) <= bytes.count - offset else { throw TokenError.invalidAccount }
            defer { offset += Int(length) }
            let text = String(validating: bytes[offset..<(offset + Int(length))], as: UTF8.self)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
            return text?.isEmpty == false ? text : nil
        }
        name = try text()
        symbol = try text()
    }
}
