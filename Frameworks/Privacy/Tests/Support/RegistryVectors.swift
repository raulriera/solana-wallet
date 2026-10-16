import Testing

/// User registry records computed by an independent Python implementation written from zolana
/// v0.4.0-alpha's sources.
///
/// The records register the sender of zolana's published transfers, with merging off, and their
/// recipient, with merging on. Addresses are Base58; bytes and field elements are hexadecimal.
struct RegistryVectors: Decodable, Sendable {
    /// The registry program's address.
    let program: String

    /// The records.
    let records: [Record]

    /// An owner's record and the shielded address it publishes.
    struct Record: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name.
        let name: String
        /// The owner's signing address.
        let owner: String
        /// The record's address.
        let record: String
        /// The record's canonical bump.
        let bump: UInt8
        /// The record's 134 bytes.
        let data: String
        /// The owner's nullifier public key.
        let nullifierPublicKey: String
        /// The owner's compressed viewing public key.
        let viewingPublicKey: String
        /// The owner's owner hash.
        let ownerHash: String

        /// The vector's name, in test results.
        var testDescription: String { name }
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The registry vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "RegistryVectors")
    }
}
