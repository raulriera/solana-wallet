import Encoding
public import Foundation

/// An initialized token account with its exact balance and authority.
public struct TokenAccount: Sendable {
    /// The account's on-chain address, which can be an ancillary token account.
    public let address: Address
    /// The program that owns this account.
    public let program: TokenProgram
    /// The mint of tokens held in the account.
    public let mint: Address
    /// The authority permitted to transfer these tokens.
    public let owner: Address
    /// The balance in integer base units.
    public let amount: UInt64
    /// Whether the token program has frozen the account.
    public let isFrozen: Bool
    let data: TokenData

    /// Decodes the account without assuming every account has the legacy size.
    ///
    /// - Parameters:
    ///   - address: The account address requested from RPC.
    ///   - programOwner: The RPC-reported account owner program.
    ///   - data: The raw base64-decoded token-account data.
    /// - Throws: ``TokenError`` for unsupported owners or malformed account data.
    public init(address: Address, programOwner: Address, data: Data) throws {
        guard let program = TokenProgram(rawValue: programOwner.value) else { throw TokenError.unsupportedProgram }
        let decoded = try TokenData(data, program: program, isMint: false)
        for offset in [72, 109, 129] { try decoded.validateOption(at: offset) }
        guard decoded.bytes[108] == 1 || decoded.bytes[108] == 2 else { throw TokenError.invalidAccount }
        self.address = address
        self.program = program
        mint = try Address(Base58.encode(Array(decoded.bytes[0..<32])))
        owner = try Address(Base58.encode(Array(decoded.bytes[32..<64])))
        amount = try TokenData.integer(decoded.bytes, at: 64)
        isFrozen = decoded.bytes[108] == 2
        self.data = decoded
    }

    /// Decodes the account at an associated token account address, which can hold SOL before its token account exists.
    ///
    /// Anyone can send SOL to the address first, which leaves an unallocated System Program account there.
    /// The initializer fails for that account, because the token account doesn't exist yet.
    ///
    /// - Parameters:
    ///   - address: The associated token account address requested from RPC.
    ///   - programOwner: The RPC-reported account owner program.
    ///   - data: The raw base64-decoded account data.
    /// - Throws: ``TokenError`` for unsupported owners, malformed account data, or a System Program account with data.
    public init?(associatedAt address: Address, programOwner: Address, data: Data) throws {
        if programOwner.value == "11111111111111111111111111111111" {
            guard data.isEmpty else { throw TokenError.invalidAccount }
            return nil
        }
        try self.init(address: address, programOwner: programOwner, data: data)
    }

    /// Checks account extensions needed by an ordinary top-level transfer.
    ///
    /// - Parameter receiving: Whether this account is the destination of the transfer.
    /// - Returns: Whether the transfer must be preceded by a memo.
    /// - Throws: ``TokenError`` for frozen accounts or unsupported extension behavior.
    func requiresMemo(receiving: Bool) throws -> Bool {
        guard !isFrozen else { throw TokenError.frozenAccount }
        var memoRequired = false
        for type in data.extensions.keys.sorted() {
            switch type {
            case 2: _ = try data.value(type, length: 8)
            case 7, 27: _ = try data.value(type, length: 0)
            case 8, 11, 15:
                let flag = try data.value(type, length: 1)![0]
                guard flag <= 1 else { throw TokenError.invalidAccount }
                if type == 8 && receiving { memoRequired = flag == 1 }
                if type == 15 && flag == 1 { throw TokenError.invalidAccount }
            case 13: throw TokenError.transferDisabled
            default: throw TokenError.unsupportedExtension(type)
            }
        }
        return memoRequired
    }
}
