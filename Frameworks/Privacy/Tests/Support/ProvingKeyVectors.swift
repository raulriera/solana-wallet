import Testing

/// zolana's lock file of the prover's proving keys.
///
/// `ProvingKeyVectors.json` copies `prover/server/prover/provingkeys/proving-keys.lock` unchanged at
/// tag v0.4.0-alpha (Apache-2.0). `ProvingKeyVectors-LICENSE.txt` records the source and its
/// digest. Each key file's entry gives its SHA-256 digest as lowercase hexadecimal.
struct ProvingKeyVectors: Decodable, Sendable {
    /// Each key file's entry, by file name.
    let keys: [String: Key]

    /// One proving key file.
    struct Key: Decodable, Sendable {
        /// The file's SHA-256 digest.
        let sha256: String
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The lock file's entries.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "ProvingKeyVectors")
    }
}
