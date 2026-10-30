import Testing
import Encoding

struct Base58Tests {
    @Test(arguments: [
        ([UInt8](repeating: 0, count: 32), String(repeating: "1", count: 32)),
        ([UInt8](arrayLiteral: 0, 0, 1), "112"),
        ([UInt8](arrayLiteral: 0, 255), "15Q"),
        ([UInt8](arrayLiteral: 255, 255), "LUv"),
    ])
    func `Base58 encoding preserves leading zero bytes`(bytes: [UInt8], expected: String) {
        #expect(Base58.encode(bytes) == expected)
    }

    @Test(arguments: [
        ("", [UInt8]()),
        ("1", [UInt8](arrayLiteral: 0)),
        ("112", [UInt8](arrayLiteral: 0, 0, 1)),
        ("15Q", [UInt8](arrayLiteral: 0, 255)),
        ("LUv", [UInt8](arrayLiteral: 255, 255)),
        ("11111111111111111111111111111111", [UInt8](repeating: 0, count: 32)),
        ("JEKNVnkbo3jma5nREBBJCDoXFVeKkD56V3xKrvRmWxFG", [UInt8](repeating: 255, count: 32))
    ])
    func `Base58 decoding preserves byte values and leading zeros`(value: String, expected: [UInt8]) {
        #expect(Base58.decode(value, byteCount: expected.count) == expected)
    }

    @Test(arguments: [
        "9WzDXwBbmkg8ZTbNMqUxvQRАyrZzDsGYdLVL9zYtAWWM",
        "9WzDXwBbmkg8ZTbNMqUxvQŁAyrZzDsGYdLVL9zYtAWWM",
        "9WzDXwBbmkg8ZTbNMqUxvQR0yrZzDsGYdLVL9zYtAWWM",
        "O", "I", "l", " 2", "2\n", "2\u{200B}"
    ])
    func `Base58 decoding rejects lookalikes and forbidden characters`(_ value: String) {
        #expect(Base58.decode(value, byteCount: 32) == nil)
    }

    @Test(arguments: [
        ("", 1), ("1", 0), ("2", -1), ("2", 2), ("12", 1), ("LUv", 1),
        ("1111111111111111111111111111111", 32),
        ("111111111111111111111111111111111", 32),
        ("11111111111111111111111111111111112", 32),
        ("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", 32)
    ])
    func `Base58 decoding rejects values that do not fit the requested byte count`(value: String, byteCount: Int) {
        #expect(Base58.decode(value, byteCount: byteCount) == nil)
    }
}
