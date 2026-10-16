import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the decoding of proofless deposit payloads against an independent implementation, and
/// the rejection of payloads that aren't default-ring deposits.
struct ProoflessOutputTests {
    /// Verifies each deposit's owner hash, blinding, mint, and amount, with and without a memo.
    ///
    /// - Parameter vector: A deposit.
    @Test(arguments: try DepositNoteVectors.load().deposits)
    func `Payloads decode to their deposits`(_ vector: DepositNoteVectors.Deposit) throws {
        let output = try ProoflessOutput(decoding: fixtureBytes(vector.payload))

        #expect(output.blinding.bigEndianBytes == (try fixtureBytes(vector.blinding)))
        #expect(output.mint == [UInt8](repeating: 0, count: 32))
        #expect(output.amount == (try #require(UInt64(vector.lamports))))
    }

    /// Verifies that payloads that aren't default-ring deposits are rejected.
    ///
    /// - Parameters:
    ///   - range: The bytes of the memo-less deposit's payload to replace.
    ///   - bytes: The replacement.
    ///   - error: The expected rejection.
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

    /// Verifies that printing, dumping, and reflecting a deposit omit its values.
    @Test
    func `Deposit diagnostics omit the values`() throws {
        let output = try ProoflessOutput(decoding: fixtureBytes(try #require(try DepositNoteVectors.load().deposits.first).payload))
        var dumped = ""
        dump(output, to: &dumped)

        #expect(String(reflecting: output) == "ProoflessOutput")
        #expect(dumped == "- ProoflessOutput\n")
    }
}
