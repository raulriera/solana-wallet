import ModularArithmetic
import Testing
@testable import Privacy

struct ProoflessOutputTests {
    @Test(arguments: try DepositNoteVectors.load().deposits.filter {
        ["deposit without memo", "deposit with memo"].contains($0.name)
    })
    func `Payloads decode to their deposits`(_ vector: DepositNoteVectors.Deposit) throws {
        let output = try ProoflessOutput(decoding: fixtureBytes(vector.payload))

        #expect(output.blinding.bigEndianBytes == (try fixtureBytes(vector.blinding)))
        #expect(output.mint == PrivateAsset.nativeSOL.mintBytes)
        #expect(output.amount == (try #require(UInt64(vector.lamports))))
    }

    @Test(arguments: [
        (0..<1, [1], .unsupportedEncoding),
        (1..<2, [0x7f], .invalidLength),
        (5..<6, [3], .unsupportedScheme),
        (6..<7, [0xff], .invalidField),
        (110..<111, [1], .unsupportedData),
        (115..<116, [2], .invalidLength),
        (115..<116, [1], .invalidLength),
    ] as [(Range<Int>, [UInt8], ProoflessOutput.ValidationError)])
    func `Invalid payloads are rejected`(range: Range<Int>, bytes: [UInt8], error: ProoflessOutput.ValidationError) throws {
        let vector = try #require(try DepositNoteVectors.load().deposits.first)
        let payload = try fixtureBytes(vector.payload).replacingSubrange(range, with: bytes)

        #expect(throws: error) {
            try ProoflessOutput(decoding: payload)
        }
    }
}
