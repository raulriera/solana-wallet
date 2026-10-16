import ModularArithmetic
import Testing

extension FieldElement {
    /// Decodes a canonical fixture value.
    ///
    /// - Parameter hex: 64 big-endian hexadecimal digits encoding a value below the modulus.
    /// - Throws: A test failure if the value is malformed or not canonical.
    init(hex: String) throws {
        self = try #require(Self(bigEndianBytes: fixtureBytes(hex)))
    }
}
