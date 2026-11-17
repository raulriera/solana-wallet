import Encoding
import Testing

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
        ("", [UInt8]()),
        ("1", [UInt8](arrayLiteral: 0)),
        ("112", [UInt8](arrayLiteral: 0, 0, 1)),
        ("15Q", [UInt8](arrayLiteral: 0, 255)),
        ("LUv", [UInt8](arrayLiteral: 255, 255)),
        ("11111111111111111111111111111111", [UInt8](repeating: 0, count: 32)),
        ("JEKNVnkbo3jma5nREBBJCDoXFVeKkD56V3xKrvRmWxFG", [UInt8](repeating: 255, count: 32)),
        ("3Bxs4fnbFx59msBM", [UInt8](arrayLiteral: 2, 0, 0, 0, 232, 191, 17, 0, 0, 0, 0, 0)),
    ])
    func `Base58 decoding up to a limit preserves byte values and leading zeros`(value: String, expected: [UInt8]) {
        #expect(Base58.decode(value, maximumCount: 32) == expected)
    }

    @Test(arguments: [
        "0", "O", "I", "l", " 2", "2\n", "2\u{200B}",
        "9WzDXwBbmkg8ZTbNMqUxvQRАyrZzDsGYdLVL9zYtAWWM",
        "9WzDXwBbmkg8ZTbNMqUxvQŁAyrZzDsGYdLVL9zYtAWWM",
        "9WzDXwBbmkg8ZTbNMqUxvQR0yrZzDsGYdLVL9zYtAWWM",
    ])
    func `Base58 decoding up to a limit rejects lookalikes and forbidden characters`(_ value: String) {
        #expect(Base58.decode(value, maximumCount: 32) == nil)
    }

    @Test(arguments: [
        ("LUv", 1), ("112", 2), ("JEKNVnkbo3jma5nREBBJCDoXFVeKkD56V3xKrvRmWxFG", 31),
        (String(repeating: "1", count: 33), 32), (String(repeating: "z", count: 1_000_000), 4_096), ("2", -1),
    ])
    func `Base58 decoding up to a limit rejects text that encodes more bytes`(value: String, maximumCount: Int) {
        #expect(Base58.decode(value, maximumCount: maximumCount) == nil)
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
