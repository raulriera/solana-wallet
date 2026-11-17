import Encoding
public import Foundation

/// A token's display name and ticker symbol, read from its on-chain metadata.
public struct TokenMetadata: Codable, Hashable, Sendable {
    public let name: String?
    /// The ticker symbol.
    public let symbol: String?

    /// Creates metadata, keeping a name or symbol only when it has text other than whitespace and null characters.
    ///
    /// - Parameters:
    ///   - name: The display name, or `nil` if unknown.
    ///   - symbol: The ticker symbol, or `nil` if unknown.
    public init(name: String?, symbol: String?) {
        self.name = name.flatMap(Self.text)
        self.symbol = symbol.flatMap(Self.text)
    }

    /// Derives the address of a mint's Metaplex metadata account.
    ///
    /// - Parameter mint: The token's mint address.
    /// - Returns: The metadata account address.
    /// - Throws: ``ValidationError/addressDerivationFailed`` if no valid bump exists.
    public static func metaplexAccount(for mint: Address) throws -> Address {
        let program = try MetaplexProgram.address
        return try ProgramAddress.find(seeds: [Array("metadata".utf8), program.bytes, mint.bytes], program: program).address
    }

    /// Reads the name and symbol from a mint's Metaplex metadata account.
    ///
    /// - Parameters:
    ///   - data: The account's raw bytes.
    ///   - owner: The account's owner program.
    ///   - mint: The mint that the account must describe.
    /// - Throws: ``TokenError/invalidAccount`` if the account isn't valid metadata for the mint.
    public init(metaplexAccount data: Data, owner: Address, mint: Address) throws {
        let bytes = Array(data)
        guard owner.value == MetaplexProgram.id, bytes.first == 4, bytes.count >= 65,
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
        guard bytes.count >= 64, Array(bytes[32..<64]) == mint.bytes else { throw TokenError.invalidAccount }
        try self.init(fields: bytes, at: 64)
    }

    /// Reads the name and symbol from consecutive length-prefixed strings.
    ///
    /// - Parameters:
    ///   - bytes: The metadata's bytes.
    ///   - offset: The position of the name's length.
    /// - Throws: ``TokenError/invalidAccount`` if a string runs past the end of the bytes.
    private init(fields bytes: [UInt8], at offset: Int) throws {
        var reader = ByteReader(bytes, at: offset, error: TokenError.invalidAccount)
        func text() throws -> String? {
            let length: UInt32 = try reader.integer()
            return String(validating: try reader.read(count: Int(length)), as: UTF8.self)
        }
        let name = try text()
        try self.init(name: name, symbol: text())
    }

    /// Returns a name or symbol without surrounding whitespace and null characters.
    ///
    /// - Parameter text: The raw text.
    /// - Returns: The trimmed text, or `nil` when nothing is left.
    private static func text(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        return trimmed.isEmpty ? nil : trimmed
    }
}
