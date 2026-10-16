import Testing
@testable import RPC

/// Verifies the prover's hexadecimal text for field elements.
struct FieldHexTests {
    /// Verifies encoding uses lowercase digits without leading zeros.
    ///
    /// - Parameters:
    ///   - bytes: The big-endian value.
    ///   - expected: Its text.
    @Test(arguments: [
        ([UInt8](repeating: 0, count: 32), "0x0"),
        ([UInt8](repeating: 0, count: 31) + [1], "0x1"),
        ([UInt8](repeating: 0, count: 30) + [1, 0], "0x100"),
        ([UInt8](repeating: 0xab, count: 32), "0x" + String(repeating: "ab", count: 32)),
    ] as [([UInt8], String)])
    func `Values encode without leading zeros`(bytes: [UInt8], expected: String) {
        #expect(FieldHex.encode(bytes) == expected)
    }

    /// Verifies integers encode like field elements.
    ///
    /// - Parameters:
    ///   - value: The integer.
    ///   - expected: Its text.
    @Test(arguments: [(UInt64(0), "0x0"), (1, "0x1"), (26, "0x1a")])
    func `Integers encode without leading zeros`(value: UInt64, expected: String) {
        #expect(FieldHex.encode(integer: value) == expected)
    }

    /// Verifies decoding accepts padded and unpadded text in either case, right-aligned in 32 bytes.
    ///
    /// - Parameters:
    ///   - text: The value's text.
    ///   - last: The expected last two bytes; the others are zero.
    @Test(arguments: [
        ("0x0", [0, 0]),
        ("0x1a2", [0x01, 0xa2]),
        ("0x" + String(repeating: "0", count: 61) + "1A2", [0x01, 0xa2]),
        ("0x" + String(repeating: "0", count: 70) + "ff", [0, 0xff]),
    ] as [(String, [UInt8])])
    func `Padded and unpadded text decode`(text: String, last: [UInt8]) {
        #expect(FieldHex.decode(text) == Array(repeating: 0, count: 30) + last)
    }

    /// Verifies decoding rejects text without the prefix or digits, other characters, and values over 32 bytes.
    ///
    /// - Parameter text: Invalid text.
    @Test(arguments: ["1", "0x", "0xg", "0x 1", "-0x1", "0x1" + String(repeating: "0", count: 64)])
    func `Invalid text is rejected`(text: String) {
        #expect(FieldHex.decode(text) == nil)
    }
}
