public import Foundation

/// A mint decoded from account bytes and its RPC-reported program owner.
///
/// Decoding validates structure, not the trustworthiness or freshness of the provider.
public struct TokenMint: Sendable {
    /// The mint's on-chain address.
    public let address: Address
    /// The program that owns and processes this mint.
    public let program: TokenProgram
    /// The number of decimal places in the mint's base-unit amount.
    public let decimals: UInt8
    let data: TokenData

    /// Whether the mint describes one indivisible token, as an NFT does: no decimals and a supply of one.
    public var isNonFungible: Bool {
        decimals == 0 && (try? TokenData.integer(data.bytes, at: 36) as UInt64) == 1
    }

    /// The name and symbol from the mint's own Token-2022 metadata extension, or `nil` without one.
    ///
    /// Most SPL tokens keep their metadata in a separate Metaplex account instead; see ``TokenMetadata``.
    public var metadata: TokenMetadata? {
        data.extensions[19].flatMap { try? TokenMetadata(metadataExtension: $0, mint: address) }
    }

    /// Account extensions required by the mint extensions supported for transfers.
    private var requiredAccountExtensions: [(type: UInt16, length: UInt64)] {
        let extensions: [(mint: UInt16, account: UInt16, length: UInt64)] = [
            (1, 2, 8),   // TransferFeeConfig → TransferFeeAmount.
            (14, 15, 1), // TransferHook → TransferHookAccount, including disabled hooks.
            (26, 27, 0), // Pausable → PausableAccount, including unpaused mints.
        ]
        return extensions.filter { data.extensions[$0.mint] != nil }.map { ($0.account, $0.length) }
    }

    /// The allocation size of a new associated token account for this mint, used to query its rent.
    ///
    /// Token accounts use 165 bytes. Token-2022 accounts add an account-type byte, immutable ownership, and the
    /// account extensions that the mint's supported extensions require; transfer validation rejects other extensions.
    public var associatedAccountSize: UInt64 {
        guard program == .token2022 else { return 165 }
        // 165 base bytes, one account-type byte, and ImmutableOwner's four-byte TLV header.
        return requiredAccountExtensions.reduce(170) { $0 + 4 + $1.length }
    }

    /// Decodes an initialized mint from either supported token program.
    ///
    /// - Parameters:
    ///   - address: The address requested from RPC.
    ///   - owner: The account's program owner, distinct from a token-account authority.
    ///   - data: The raw base64-decoded account data.
    /// - Throws: ``TokenError`` for unsupported owners or malformed mint data.
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

    /// Validates supported transfer extensions and selects an explicit fee by epoch.
    ///
    /// - Parameters:
    ///   - amount: The exact base-unit debit requested by the caller.
    ///   - epoch: The ledger epoch, required only for a configured transfer fee.
    ///   - createsDestination: Whether the default account state applies.
    /// - Returns: The fee to assert on-chain, or `nil` for a mint without transfer fees.
    /// - Throws: ``TokenError`` when an extension prevents supported construction.
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
            case 10: _ = try data.value(type, length: 52) // Interest changes display, not raw transfer units.
            case 14:
                guard let hook = try data.value(type, length: 64), hook[32...].allSatisfy({ $0 == 0 }) else {
                    throw TokenError.unsupportedExtension(type)
                }
            case 18, 20, 22: _ = try data.value(type, length: 64)
            case 19: break // Metadata has variable length and doesn't change raw-unit transfers.
            case 21: _ = try data.value(type, length: 80)
            case 23: _ = try data.value(type, length: 72)
            case 25: _ = try data.value(type, length: 56) // UI scaling doesn't change raw transfer units.
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

    /// Requires the token-account extensions mandated by this mint's configuration.
    ///
    /// - Parameter account: An existing source or destination account for this mint.
    /// - Throws: ``TokenError/accountMismatch`` when a required account extension is absent.
    func validateExtensions(of account: TokenAccount) throws {
        for entry in requiredAccountExtensions where account.data.extensions[entry.type] == nil {
            throw TokenError.accountMismatch
        }
    }
}
