import Testing
import Encoding

/// Verifies Base58 independently of wallet and transaction rules.
struct Base58Tests {
    /// Verifies leading zero bytes and carry propagation in Base58 encoding.
    ///
    /// - Parameters:
    ///   - bytes: The binary value to encode.
    ///   - expected: Its Base58 representation.
    @Test(arguments: [
        ([UInt8](repeating: 0, count: 32), String(repeating: "1", count: 32)),
        ([UInt8](arrayLiteral: 0, 0, 1), "112"),
        ([UInt8](arrayLiteral: 0, 255), "15Q"),
        ([UInt8](arrayLiteral: 255, 255), "LUv"),
    ])
    func `Base58 encoding preserves leading zero bytes`(bytes: [UInt8], expected: String) {
        #expect(Base58.encode(bytes) == expected)
    }

    /// Verifies decoding against known bytes without relying on the encoder as an oracle.
    ///
    /// - Parameters:
    ///   - value: A known Base58 representation.
    ///   - expected: Its exact decoded bytes, including leading zeros.
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

    /// Verifies the codec rejects invalid characters without trimming or substitutions.
    ///
    /// - Parameter value: Base58 text containing Unicode lookalikes or forbidden ASCII.
    @Test(arguments: [
        "9WzDXwBbmkg8ZTbNMqUxvQRАyrZzDsGYdLVL9zYtAWWM", // Cyrillic А, U+0410.
        "9WzDXwBbmkg8ZTbNMqUxvQŁAyrZzDsGYdLVL9zYtAWWM", // U+0141 truncates to ASCII A.
        "9WzDXwBbmkg8ZTbNMqUxvQR0yrZzDsGYdLVL9zYtAWWM",
        "O", "I", "l", " 2", "2\n", "2\u{200B}"
    ])
    func `Base58 decoding rejects lookalikes and forbidden characters`(_ value: String) {
        #expect(Base58.decode(value, byteCount: 32) == nil)
    }

    /// Verifies decoding cannot overflow, silently pad, or discard leading zero bytes.
    ///
    /// - Parameters:
    ///   - value: The text to decode.
    ///   - byteCount: A width the input cannot satisfy.
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
