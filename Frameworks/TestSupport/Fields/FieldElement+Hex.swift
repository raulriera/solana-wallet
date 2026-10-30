import ModularArithmetic
import Testing

extension FieldElement {
    init(hex: String) throws {
        self = try #require(Self(bigEndianBytes: fixtureBytes(hex)))
    }
}
