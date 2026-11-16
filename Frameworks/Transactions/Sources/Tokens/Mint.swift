public import Foundation

/// A token mint.
///
/// A saved mint keeps its address, program, decimals, and metadata, and not its account data.
public struct Mint: Codable, Hashable, Sendable {
    public let address: Address
    public let program: TokenProgram
    public let decimals: UInt8
    /// The name and symbol from the mint's metadata extension or its Metaplex account, or `nil` without either.
    public var metadata: TokenMetadata?
    /// The validated account data, or `nil` for a mint created from known facts or read from a saved value.
    private(set) var data: TokenData?

    /// The saved fields, which leave out the account data.
    private enum CodingKeys: String, CodingKey {
        case address, program, decimals, metadata
    }

    /// The mint's account data.
    ///
    /// - Throws: ``TokenError/invalidAccount`` for a mint without account data.
    private var accountData: TokenData {
        get throws {
            guard let data else { throw TokenError.invalidAccount }
            return data
        }
    }

    /// A Boolean value that indicates whether the mint has no decimals and a supply of one.
    ///
    /// - Throws: ``TokenError/invalidAccount`` for a mint without account data.
    public var isNonFungible: Bool {
        get throws {
            let supply: UInt64 = try TokenData.integer(accountData.bytes, at: 36)
            return decimals == 0 && supply == 1
        }
    }

    /// The account extensions, with their lengths, that the mint's extensions require.
    ///
    /// - Throws: ``TokenError/invalidAccount`` for a mint without account data.
    private var requiredAccountExtensions: [(type: UInt16, length: UInt64)] {
        get throws {
            let data = try accountData
            let extensions: [(mint: UInt16, account: UInt16, length: UInt64)] = [
                (1, 2, 8),
                (14, 15, 1),
                (26, 27, 0),
            ]
            return extensions.filter { data.extensions[$0.mint] != nil }.map { ($0.account, $0.length) }
        }
    }

    /// The size in bytes of a new associated token account for the mint.
    ///
    /// - Throws: ``TokenError/invalidAccount`` for a mint without account data.
    public var associatedAccountSize: UInt64 {
        get throws {
            let required = try requiredAccountExtensions
            guard program == .token2022 else { return 165 }
            return required.reduce(170) { $0 + 4 + $1.length }
        }
    }

    /// Creates a mint from known facts, without account data.
    ///
    /// - Parameters:
    ///   - address: The mint address.
    ///   - program: The program that owns the mint.
    ///   - decimals: The number of decimal places in base-unit amounts.
    ///   - metadata: The name and symbol, or `nil` if unknown.
    public init(address: Address, program: TokenProgram, decimals: UInt8, metadata: TokenMetadata?) {
        self.address = address
        self.program = program
        self.decimals = decimals
        self.metadata = metadata
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
        metadata = decoded.extensions[19].flatMap { try? TokenMetadata(metadataExtension: $0, mint: address) }
        self.data = decoded
    }

    /// Validates the mint's extensions for a transfer and returns its fee.
    ///
    /// - Parameters:
    ///   - amount: The debit in base units.
    ///   - epoch: The current epoch, or `nil` for a mint without transfer fees.
    ///   - createsDestination: Whether the transfer creates the destination account.
    /// - Returns: The transfer fee, or `nil` for a mint without transfer fees.
    /// - Throws: A ``TokenError`` for an unsupported or blocking extension, or for a mint without account data.
    func transferFee(amount: UInt64, epoch: UInt64?, createsDestination: Bool) throws -> UInt64? {
        let data = try accountData
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
    /// - Throws: ``TokenError/accountMismatch`` if a required extension is missing, or
    ///   ``TokenError/invalidAccount`` for a mint without account data.
    func validateExtensions(of account: Token) throws {
        for entry in try requiredAccountExtensions where account.data.extensions[entry.type] == nil {
            throw TokenError.accountMismatch
        }
    }
}
