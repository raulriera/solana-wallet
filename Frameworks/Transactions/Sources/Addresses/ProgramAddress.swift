import CryptoKit

/// A namespace for deriving program-derived addresses.
public enum ProgramAddress {
    /// The most seeds an address takes, including the bump.
    private static let maximumSeedCount = 16

    private static let maximumSeedLength = 32

    /// Derives the canonical program-derived address for seeds.
    ///
    /// - Parameters:
    ///   - seeds: The seeds in order, without the bump: at most 15, each at most 32 bytes.
    ///   - program: The program that owns the derived address.
    /// - Returns: The canonical program address and its bump.
    /// - Throws: ``ValidationError/invalidSeeds`` or ``ValidationError/addressDerivationFailed``.
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
