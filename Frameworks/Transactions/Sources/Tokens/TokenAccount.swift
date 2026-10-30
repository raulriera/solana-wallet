public import Foundation

/// An initialized token account with its balance and owner.
public struct TokenAccount: Sendable {
    public let address: Address
    public let program: TokenProgram
    public let mint: Address
    /// The authority that can transfer the tokens.
    public let owner: Address
    /// The balance in base units.
    public let amount: UInt64
    public let isFrozen: Bool
    let data: TokenData

    /// Creates a token account by decoding its data.
    ///
    /// - Parameters:
    ///   - address: The account address.
    ///   - programOwner: The account's owner program.
    ///   - data: The account's raw data.
    /// - Throws: A ``TokenError`` for an unsupported owner or malformed data.
    public init(address: Address, programOwner: Address, data: Data) throws {
        guard let program = TokenProgram(rawValue: programOwner.value) else { throw TokenError.unsupportedProgram }
        let decoded = try TokenData(data, program: program, isMint: false)
        for offset in [72, 109, 129] { try decoded.validateOption(at: offset) }
        guard decoded.bytes[108] == 1 || decoded.bytes[108] == 2 else { throw TokenError.invalidAccount }
        self.address = address
        self.program = program
        mint = try Address(bytes: decoded.bytes[0..<32])
        owner = try Address(bytes: decoded.bytes[32..<64])
        amount = try TokenData.integer(decoded.bytes, at: 64)
        isFrozen = decoded.bytes[108] == 2
        self.data = decoded
    }

    /// Creates the token account at an associated token account address, or `nil` if it doesn't exist yet.
    ///
    /// - Parameters:
    ///   - address: The associated token account address.
    ///   - programOwner: The account's owner program.
    ///   - data: The account's raw data.
    /// - Throws: A ``TokenError`` for an unsupported owner, malformed data, or a System Program account with data.
    public init?(associatedAt address: Address, programOwner: Address, data: Data) throws {
        if programOwner.value == SystemProgram.id {
            guard data.isEmpty else { throw TokenError.invalidAccount }
            return nil
        }
        try self.init(address: address, programOwner: programOwner, data: data)
    }

    /// Checks the account's state and extensions for a transfer.
    ///
    /// - Parameter receiving: Whether the account receives the transfer.
    /// - Returns: Whether a memo must precede the transfer.
    /// - Throws: A ``TokenError`` for a frozen account or an unsupported extension.
    func requiresMemo(receiving: Bool) throws -> Bool {
        guard !isFrozen else { throw TokenError.frozenAccount }
        var memoRequired = false
        for type in data.extensions.keys.sorted() {
            switch type {
            case 2: _ = try data.value(type, length: 8)
            case 7, 27: _ = try data.value(type, length: 0)
            case 8, 11, 15:
                guard let flag = try data.value(type, length: 1)?[0], flag <= 1 else { throw TokenError.invalidAccount }
                if type == 8 && receiving { memoRequired = flag == 1 }
                if type == 15 && flag == 1 { throw TokenError.invalidAccount }
            case 13: throw TokenError.transferDisabled
            default: throw TokenError.unsupportedExtension(type)
            }
        }
        return memoRequired
    }
}
