import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the encoding of confidential notes.
///
/// The expected bytes come from a separate Python implementation of the note's layout.
struct ConfidentialPlaintextTests {
    /// The encoding of a SOL note of 0x0123456789abcdef lamports with the blinding r - 1, whose
    /// amount bytes differ in each position.
    private static let encoding = "0100000000000000efcdab896745230130644e72e131a029b85045b68181585d2833e84879b9709143e1f593f00000000000"

    /// The note that ``encoding`` encodes.
    private static let note = ConfidentialPlaintext(asset: .sol, amount: 0x0123_4567_89ab_cdef, blinding: -.one)

    /// Verifies that a note encodes to independently derived bytes.
    @Test
    func `Notes encode to independently derived bytes`() throws {
        #expect(Self.note.encoded == (try fixtureBytes(Self.encoding)))
    }

    /// Verifies that independently derived bytes decode to their note.
    @Test
    func `Notes decode from independently derived bytes`() throws {
        #expect(try ConfidentialPlaintext(decoding: fixtureBytes(Self.encoding)) == Self.note)
    }

    /// Verifies that notes that aren't SOL notes without a ring program or data are rejected.
    ///
    /// - Parameters:
    ///   - bytes: A malformed or unsupported note.
    ///   - error: The expected rejection.
    @Test(arguments: try ConfidentialPlaintextTests.unsupportedNotes())
    func `Unsupported notes are rejected`(bytes: [UInt8], error: ConfidentialPlaintext.ValidationError) {
        #expect(throws: error) {
            try ConfidentialPlaintext(decoding: bytes)
        }
    }

    /// Verifies that printing, dumping, and reflecting a note omit its amount and blinding.
    @Test
    func `Note diagnostics omit the amount and blinding`() {
        var output = ""
        dump(Self.note, to: &output)

        #expect(Self.note.description == "ConfidentialPlaintext")
        #expect(Self.note.debugDescription == "ConfidentialPlaintext")
        #expect(String(reflecting: Self.note) == "ConfidentialPlaintext")
        #expect(output == "- ConfidentialPlaintext\n")
        #expect(Mirror(reflecting: Self.note).children.isEmpty)
    }

    /// Builds unsupported notes from the independently derived encoding.
    ///
    /// The cases are no bytes, one byte too few, and one trailing byte; the asset IDs 0, 2, and
    /// 2^56, whose bytes read as 1 in big-endian order; the blindings r and 2^256 - 1; a ring
    /// program; and a one-byte memo record.
    ///
    /// - Returns: Each note and its expected rejection.
    /// - Throws: A test failure if the encoding is malformed.
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
            // One record: the memo tag 3, a little-endian 16-bit length of 1, and the memo byte.
            (note.replacingSubrange(49..<50, with: [1, 3, 1, 0, 0x2a]), .unsupportedData),
        ]
    }
}
