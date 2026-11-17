import ModularArithmetic
import Testing
@testable import Privacy

struct ConfidentialPlaintextTests {
    private static let encoding = "0100000000000000efcdab896745230130644e72e131a029b85045b68181585d2833e84879b9709143e1f593f00000000000"

    private static let note = ConfidentialPlaintext(asset: .nativeSOL, amount: 0x0123_4567_89ab_cdef, blinding: -.one)

    @Test
    func `Notes encode to independently derived bytes`() throws {
        #expect(Self.note.encoded == (try fixtureBytes(Self.encoding)))
    }

    @Test
    func `Notes decode from independently derived bytes`() throws {
        #expect(try ConfidentialPlaintext(decoding: fixtureBytes(Self.encoding)) == Self.note)
    }

    @Test(arguments: PrivateAsset.allCases)
    func `Notes of every supported asset round-trip`(asset: PrivateAsset) throws {
        let note = ConfidentialPlaintext(asset: asset, amount: 42, blinding: .one)

        #expect(try ConfidentialPlaintext(decoding: note.encoded) == note)
    }

    @Test(arguments: try ConfidentialPlaintextTests.unsupportedNotes())
    func `Unsupported notes are rejected`(bytes: [UInt8], error: ConfidentialPlaintext.ValidationError) {
        #expect(throws: error) {
            try ConfidentialPlaintext(decoding: bytes)
        }
    }

    private static func unsupportedNotes() throws -> [([UInt8], ConfidentialPlaintext.ValidationError)] {
        let note = try fixtureBytes(encoding)
        let modulus = try fixtureBytes("30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001")
        return [
            ([], .invalidLength),
            (Array(note.dropLast()), .invalidLength),
            (note + [0], .invalidLength),
            (note.replacingSubrange(0..<8, with: [0, 0, 0, 0, 0, 0, 0, 0]), .unsupportedAsset),
            (note.replacingSubrange(0..<8, with: [2, 0, 0, 0, 0, 0, 0, 0]), .unsupportedAsset),
            (note.replacingSubrange(0..<8, with: [0, 0, 0, 0, 0, 0, 0, 1]), .unsupportedAsset),
            (note.replacingSubrange(16..<48, with: modulus), .nonCanonicalBlinding),
            (note.replacingSubrange(16..<48, with: [UInt8](repeating: 0xff, count: 32)), .nonCanonicalBlinding),
            (note.replacingSubrange(48..<50, with: [1] + [UInt8](repeating: 7, count: 32) + [0]), .unsupportedRingProgram),
            (note.replacingSubrange(49..<50, with: [1, 3, 1, 0, 0x2a]), .unsupportedData),
        ]
    }
}
