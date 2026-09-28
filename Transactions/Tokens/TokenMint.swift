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

    /// Derives the wallet's associated token account using this mint's program.
    ///
    /// - Parameter owner: The receiving wallet, including program-derived wallets.
    /// - Returns: The canonical associated account to query or create.
    /// - Throws: ``TokenError/addressDerivationFailed`` if no valid bump exists.
    public func associatedAccount(for owner: Address) throws -> Address {
        try ProgramAddress.associatedAccount(owner: owner, mint: address, program: program)
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
                let state = try data.value(type, length: 1)![0]
                guard state == 1 || state == 2 else { throw TokenError.invalidAccount }
                if createsDestination && state == 2 { throw TokenError.frozenAccount }
            case 9: throw TokenError.transferDisabled
            case 10: _ = try data.value(type, length: 52) // Interest changes display, not raw transfer units.
            case 14:
                let hook = try data.value(type, length: 64)!
                guard hook[32...].allSatisfy({ $0 == 0 }) else { throw TokenError.unsupportedExtension(type) }
            case 18, 20, 22: _ = try data.value(type, length: 64)
            case 19: break // Metadata has variable length and doesn't change raw-unit transfers.
            case 21: _ = try data.value(type, length: 80)
            case 23: _ = try data.value(type, length: 72)
            case 25: _ = try data.value(type, length: 56) // UI scaling doesn't change raw transfer units.
            case 26:
                let paused = try data.value(type, length: 33)![32]
                guard paused <= 1 else { throw TokenError.invalidAccount }
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
        for (mintExtension, accountExtension): (UInt16, UInt16) in [(1, 2), (14, 15), (26, 27)] {
            if data.extensions[mintExtension] != nil, account.data.extensions[accountExtension] == nil {
                throw TokenError.accountMismatch
            }
        }
    }
}
