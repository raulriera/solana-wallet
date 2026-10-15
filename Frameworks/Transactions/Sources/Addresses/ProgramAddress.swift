import CryptoKit

/// Derives public program addresses using Solana's descending bump search.
enum ProgramAddress {
    /// Derives the canonical address for seeds: the one with the highest bump that is off the curve.
    ///
    /// - Parameters:
    ///   - seeds: The seeds in order.
    ///   - program: The program that owns the derived address.
    /// - Returns: The canonical program address.
    /// - Throws: ``TokenError/addressDerivationFailed`` if every bump is on-curve.
    static func find(seeds: [[UInt8]], program: Address) throws -> Address {
        let seeds = seeds.flatMap(\.self)
        for bump in stride(from: 255, through: 1, by: -1) {
            let input = seeds + [UInt8(bump)] + program.bytes + Array("ProgramDerivedAddress".utf8)
            let hash = Array(SHA256.hash(data: input))
            if !EdwardsPoint.isOnCurve(hash) { return try Address(bytes: hash) }
        }
        throw TokenError.addressDerivationFailed
    }
}
