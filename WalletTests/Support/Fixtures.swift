import Foundation
import Testing

/// Public BIP-39 reference data; none of these phrases may secure real funds.
struct BIP39Vector: Decodable, Sendable {
    let entropy: String
    let phrase: String
    let seed: String

    /// Reads published English vectors and two supplemental standard phrase lengths.
    ///
    /// The first 24 records come from Trezor's python-mnemonic vectors.json (MIT).
    /// The last two use zero entropy and Python hashlib for the 15- and 21-word cases.
    ///
    /// - Returns: Entropy, phrase, and seed examples using the passphrase `TREZOR`.
    /// - Throws: An error if the test resource can't be read or decoded.
    static func examples() throws -> [Self] {
        let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "BIP39", withExtension: "json"))
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }
}

/// Identifies the test bundle containing the public reference fixtures.
private final class FixtureBundle: NSObject {}

/// Decodes hexadecimal fixture bytes.
///
/// - Parameter hex: An even number of hexadecimal digits from a public test vector.
/// - Returns: The bytes in their original order.
/// - Throws: A test failure if the fixture is malformed.
func fixtureBytes(_ hex: String) throws -> [UInt8] {
    let characters = Array(hex)
    try #require(characters.count.isMultiple(of: 2))
    return try stride(from: 0, to: characters.count, by: 2).map { index in
        try #require(UInt8(String(characters[index...index + 1]), radix: 16))
    }
}
