import CryptoKit

/// Derives program-derived addresses using Solana's descending bump search.
///
/// The address for seeds and a bump is `SHA-256(seeds ‖ bump ‖ program ‖ "ProgramDerivedAddress")`,
/// valid only off the Ed25519 curve. The search tries bumps from 255 down to 1, as Solana's
/// `find_program_address` does, and returns the first valid one, the canonical bump.
public enum ProgramAddress {
    /// The most seeds that an address takes, including the bump.
    private static let maximumSeedCount = 16

    /// The most bytes in one seed.
    private static let maximumSeedLength = 32

    /// Derives the canonical address for seeds: the one with the highest bump that is off the curve.
    ///
    /// - Parameters:
    ///   - seeds: The seeds in order, without the bump: at most 15, each at most 32 bytes.
    ///   - program: The program that owns the derived address.
    /// - Returns: The canonical program address and its bump.
    /// - Throws: ``ValidationError/invalidSeeds`` for more than 15 seeds or a seed longer than
    ///   32 bytes, or ``ValidationError/addressDerivationFailed`` if every bump is on the curve.
    public static func find(seeds: [[UInt8]], program: Address) throws -> (address: Address, bump: UInt8) {
        guard seeds.count < maximumSeedCount, seeds.allSatisfy({ $0.count <= maximumSeedLength }) else {
            throw ValidationError.invalidSeeds
        }
        let seeds = seeds.flatMap(\.self)
        for bump in stride(from: UInt8.max, through: 1, by: -1) {
            let input = seeds + [bump] + program.bytes + Array("ProgramDerivedAddress".utf8)
            let hash = Array(SHA256.hash(data: input))
            if !EdwardsPoint.isOnCurve(hash) { return (try Address(bytes: hash), bump) }
        }
        throw ValidationError.addressDerivationFailed
    }
}
