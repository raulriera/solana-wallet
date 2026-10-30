import Testing
@testable import RPC

struct FieldHexTests {
    @Test(arguments: [
        ([UInt8](repeating: 0, count: 32), "0x0"),
        ([UInt8](repeating: 0, count: 31) + [1], "0x1"),
        ([UInt8](repeating: 0, count: 30) + [1, 0], "0x100"),
        ([UInt8](repeating: 0xab, count: 32), "0x" + String(repeating: "ab", count: 32)),
    ] as [([UInt8], String)])
    func `Values encode without leading zeros`(bytes: [UInt8], expected: String) {
        #expect(FieldHex.encode(bytes) == expected)
    }

    @Test(arguments: [(UInt64(0), "0x0"), (1, "0x1"), (26, "0x1a")])
    func `Integers encode without leading zeros`(value: UInt64, expected: String) {
        #expect(FieldHex.encode(integer: value) == expected)
    }

    @Test(arguments: [
        ("0x0", [0, 0]),
        ("0x1a2", [0x01, 0xa2]),
        ("0x" + String(repeating: "0", count: 61) + "1A2", [0x01, 0xa2]),
        ("0x" + String(repeating: "0", count: 70) + "ff", [0, 0xff]),
    ] as [(String, [UInt8])])
    func `Padded and unpadded text decode`(text: String, last: [UInt8]) {
        #expect(FieldHex.decode(text) == Array(repeating: 0, count: 30) + last)
    }

    @Test(arguments: ["1", "0x", "0xg", "0x 1", "-0x1", "0x1" + String(repeating: "0", count: 64)])
    func `Invalid text is rejected`(text: String) {
        #expect(FieldHex.decode(text) == nil)
    }
}
