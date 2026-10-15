import CryptoKit
import Testing

/// The parts of zolana's Poseidon parity fixture that these tests use.
///
/// `PoseidonParity.json` is an unchanged copy of `sdk-libs/ts/vectors/poseidon-parity-v1.json` at
/// tag v0.4.0-alpha (Apache-2.0); `PoseidonParity-LICENSE.txt` records its source and digest.
/// Every value is 64 big-endian hexadecimal digits.
struct PoseidonParity: Decodable, Sendable {
    /// The published parameters.
    let parameters: Parameters

    /// Hash vectors for one to twelve inputs, eight to twelve for each input count.
    let vectors: [Vector]

    /// The published parameters of every width.
    struct Parameters: Decodable, Sendable {
        /// The number of full rounds of every width.
        let roundsFull: Int
        /// One entry for each width from 2 to 13.
        let perArity: [Width]
    }

    /// The published rounds and constant digests of one width.
    ///
    /// Each digest has the format that ``PoseidonParity/digest(of:)`` computes.
    struct Width: Decodable, Sendable, CustomTestStringConvertible {
        /// The number of state elements, t.
        let width: Int
        /// The number of partial rounds.
        let roundsPartial: Int
        /// The published number of round constants.
        let arkCount: Int
        /// The digest of the round constants, in hexadecimal.
        let arkSha256: String
        /// The digest of the MDS matrix, in hexadecimal.
        let mdsSha256: String

        /// The width, in test results.
        var testDescription: String { "Width \(width)" }

        /// The published digest of the round constants in order.
        ///
        /// - Throws: A test failure if the fixture's digest is malformed.
        var roundConstantDigest: [UInt8] {
            get throws { try fixtureBytes(arkSha256) }
        }

        /// The published digest of the MDS matrix entries by row.
        ///
        /// - Throws: A test failure if the fixture's digest is malformed.
        var matrixDigest: [UInt8] {
            get throws { try fixtureBytes(mdsSha256) }
        }
    }

    /// A published hash of canonical inputs.
    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's identifier in the fixture.
        let id: String
        /// One to twelve canonical inputs.
        let inputsBytes: [String]
        /// The expected hash.
        let expectedBytes: String

        /// The vector's identifier, in test results.
        var testDescription: String { id }
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The published parameters and vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "PoseidonParity")
    }

    /// Computes a digest in the format of the published digests.
    ///
    /// The digest is SHA-256 over the 32-byte big-endian encodings of the values in order. The
    /// fixture doesn't specify this format; it reproduces the published digests.
    ///
    /// - Parameter values: 32-byte big-endian values, in order.
    /// - Returns: The 32-byte digest.
    static func digest(of values: some Sequence<[UInt8]>) -> [UInt8] {
        Array(SHA256.hash(data: Array(values.joined())))
    }
}
