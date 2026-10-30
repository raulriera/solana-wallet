public import Foundation

/// A token mint decoded from its account data.
public struct TokenMint: Sendable {
    public let address: Address
    public let program: TokenProgram
    public let decimals: UInt8
    let data: TokenData

    /// A Boolean value that indicates whether the mint has no decimals and a supply of one.
    public var isNonFungible: Bool {
        decimals == 0 && (try? TokenData.integer(data.bytes, at: 36) as UInt64) == 1
    }

    /// The name and symbol from the mint's Token-2022 metadata extension, or `nil` without one.
    public var metadata: TokenMetadata? {
        data.extensions[19].flatMap { try? TokenMetadata(metadataExtension: $0, mint: address) }
    }

    /// The account extensions, with their lengths, that the mint's extensions require.
    private var requiredAccountExtensions: [(type: UInt16, length: UInt64)] {
        let extensions: [(mint: UInt16, account: UInt16, length: UInt64)] = [
            (1, 2, 8),
            (14, 15, 1),
            (26, 27, 0),
        ]
        return extensions.filter { data.extensions[$0.mint] != nil }.map { ($0.account, $0.length) }
    }

    /// The size in bytes of a new associated token account for the mint.
    public var associatedAccountSize: UInt64 {
        guard program == .token2022 else { return 165 }
        return requiredAccountExtensions.reduce(170) { $0 + 4 + $1.length }
    }

    /// Creates a mint by decoding its account data.
    ///
    /// - Parameters:
    ///   - address: The mint address.
    ///   - owner: The account's owner program.
    ///   - data: The account's raw data.
    /// - Throws: A ``TokenError`` for an unsupported owner or malformed data.
    public init(address: Address, owner: Address, data: Data) throws {
        guard let program = TokenProgram(rawValue: owner.value) else { throw TokenError.unsupportedProgram }
        let decoded = try TokenData(data, program: program, isMint: true)
        try decoded.validateOption(at: 0)
        try decoded.validateOption(at: 46)
        guard decoded.bytes[45] == 1 else { throw TokenError.invalidAccount }
        self.address = address
        self.program = program
        decimals = decoded.bytes[44]
        self.data = decoded
    }

    /// Validates the mint's extensions for a transfer and returns its fee.
    ///
    /// - Parameters:
    ///   - amount: The debit in base units.
    ///   - epoch: The current epoch, or `nil` for a mint without transfer fees.
    ///   - createsDestination: Whether the transfer creates the destination account.
    /// - Returns: The transfer fee, or `nil` for a mint without transfer fees.
    /// - Throws: A ``TokenError`` for an unsupported or blocking extension.
    func transferFee(amount: UInt64, epoch: UInt64?, createsDestination: Bool) throws -> UInt64? {
        for type in data.extensions.keys.sorted() {
            switch type {
            case 1: _ = try data.value(type, length: 108)
            case 3, 12: _ = try data.value(type, length: 32)
            case 6:
                guard let state = try data.value(type, length: 1)?[0], state == 1 || state == 2 else {
                    throw TokenError.invalidAccount
                }
                if createsDestination && state == 2 { throw TokenError.frozenAccount }
            case 9: throw TokenError.transferDisabled
            case 10: _ = try data.value(type, length: 52)
            case 14:
                guard let hook = try data.value(type, length: 64), hook[32...].allSatisfy({ $0 == 0 }) else {
                    throw TokenError.unsupportedExtension(type)
                }
            case 18, 20, 22: _ = try data.value(type, length: 64)
            case 19: break
            case 21: _ = try data.value(type, length: 80)
            case 23: _ = try data.value(type, length: 72)
            case 25: _ = try data.value(type, length: 56)
            case 26:
                guard let paused = try data.value(type, length: 33)?[32], paused <= 1 else {
                    throw TokenError.invalidAccount
                }
                if paused == 1 { throw TokenError.transferDisabled }
            default: throw TokenError.unsupportedExtension(type)
            }
        }
        guard let fee = try data.value(1, length: 108) else { return nil }
        guard let epoch else { throw TokenError.epochRequired }
        let newEpoch: UInt64 = try TokenData.integer(fee, at: 90)
        let oldRate: UInt16 = try TokenData.integer(fee, at: 88)
        let newRate: UInt16 = try TokenData.integer(fee, at: 106)
        guard oldRate <= 10_000, newRate <= 10_000 else { throw TokenError.invalidAccount }
        let offset = epoch >= newEpoch ? 90 : 72
        let maximum: UInt64 = try TokenData.integer(fee, at: offset + 8)
        let rate: UInt16 = try TokenData.integer(fee, at: offset + 16)
        let roundedUp = (UInt128(amount) * UInt128(rate) + 9_999) / 10_000
        return UInt64(min(roundedUp, UInt128(maximum)))
    }

    /// Checks that an account has the extensions the mint requires.
    ///
    /// - Parameter account: A source or destination account for the mint.
    /// - Throws: ``TokenError/accountMismatch`` if a required extension is missing.
    func validateExtensions(of account: TokenAccount) throws {
        for entry in requiredAccountExtensions where account.data.extensions[entry.type] == nil {
            throw TokenError.accountMismatch
        }
    }
}
