import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

struct ConfidentialPlaintextTests {
    private static let encoding = "0100000000000000efcdab896745230130644e72e131a029b85045b68181585d2833e84879b9709143e1f593f00000000000"

    private static let note = ConfidentialPlaintext(asset: .sol, amount: 0x0123_4567_89ab_cdef, blinding: -.one)

    @Test
    func `Notes encode to independently derived bytes`() throws {
        #expect(Self.note.encoded == (try fixtureBytes(Self.encoding)))
    }

    @Test
    func `Notes decode from independently derived bytes`() throws {
        #expect(try ConfidentialPlaintext(decoding: fixtureBytes(Self.encoding)) == Self.note)
    }

    @Test(arguments: ConfidentialPlaintext.Asset.allCases)
    func `Notes of every supported asset round-trip`(asset: ConfidentialPlaintext.Asset) throws {
        let note = ConfidentialPlaintext(asset: asset, amount: 42, blinding: .one)

        #expect(try ConfidentialPlaintext(decoding: note.encoded) == note)
    }

    @Test(arguments: [
        (ConfidentialPlaintext.Asset.usdc, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
        (.usdt, "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"),
        (.devnetUSDC, "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"),
    ])
    func `Token assets carry their mints`(asset: ConfidentialPlaintext.Asset, mint: String) throws {
        let bytes = try Address(mint).bytes

        #expect(asset.mint == bytes)
        #expect(ConfidentialPlaintext.Asset(mint: bytes) == asset)
    }

    @Test
    func `Other mints have no asset`() {
        #expect(ConfidentialPlaintext.Asset(mint: [UInt8](repeating: 7, count: 32)) == nil)
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
