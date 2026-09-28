import CryptoKit
import Encoding

/// Derives public program addresses using Solana's descending bump search.
enum ProgramAddress {
    /// Derives the associated token account for a wallet, mint, and token program.
    ///
    /// - Parameters:
    ///   - owner: The wallet that owns the token account, including an off-curve owner.
    ///   - mint: The mint whose tokens the account holds.
    ///   - program: The token program that owns the mint.
    /// - Returns: The canonical associated token account address.
    /// - Throws: ``TokenError/addressDerivationFailed`` if every bump is on-curve.
    static func associatedAccount(owner: Address, mint: Address, program: TokenProgram) throws -> Address {
        let tokenProgram = try Address(program.rawValue)
        let associatedProgram = try Address("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
        let seeds = owner.bytes + tokenProgram.bytes + mint.bytes
        for bump in stride(from: 255, through: 1, by: -1) {
            let input = seeds + [UInt8(bump)] + associatedProgram.bytes + Array("ProgramDerivedAddress".utf8)
            let hash = Array(SHA256.hash(data: input))
            if !EdwardsPoint.isOnCurve(hash) { return try Address(Base58.encode(hash)) }
        }
        throw TokenError.addressDerivationFailed
    }
}
