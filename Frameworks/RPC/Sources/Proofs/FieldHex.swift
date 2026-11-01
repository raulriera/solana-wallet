import Encoding

/// The prover's hexadecimal text for 32-byte big-endian values.
enum FieldHex {
    /// The order of the BN254 scalar field, as 32 big-endian bytes.
    private static let order: [UInt8] = [
        0x30, 0x64, 0x4e, 0x72, 0xe1, 0x31, 0xa0, 0x29, 0xb8, 0x50, 0x45, 0xb6, 0x81, 0x81, 0x58, 0x5d,
        0x28, 0x33, 0xe8, 0x48, 0x79, 0xb9, 0x70, 0x91, 0x43, 0xe1, 0xf5, 0x93, 0xf0, 0x00, 0x00, 0x01,
    ]

    /// Returns whether bytes are a canonical BN254 scalar field element.
    ///
    /// - Parameter bytes: The big-endian value.
    /// - Returns: `true` for 32 bytes below the field's order.
    static func isCanonical(_ bytes: [UInt8]) -> Bool {
        bytes.count == 32 && bytes.lexicographicallyPrecedes(order)
    }

    /// Encodes big-endian bytes as `0x` and lowercase digits without leading zeros.
    ///
    /// - Parameter bytes: The big-endian value.
    /// - Returns: The value's text, `0x0` for zero.
    static func encode(_ bytes: [UInt8]) -> String {
        let digits = Hex.encode(bytes).drop { $0 == "0" }
        return "0x" + (digits.isEmpty ? "0" : digits)
    }

    /// Encodes an integer as `0x` and lowercase digits without leading zeros.
    ///
    /// - Parameter value: The integer.
    /// - Returns: The value's text, `0x0` for zero.
    static func encode(integer value: UInt64) -> String {
        "0x" + String(value, radix: 16)
    }

    /// Decodes `0x` and one or more hexadecimal digits, with or without leading zeros, as 32 big-endian bytes.
    ///
    /// - Parameter text: The value's text.
    /// - Returns: The value right-aligned in 32 bytes, or `nil` for invalid text or a value of more than 32 bytes.
    static func decode(_ text: String) -> [UInt8]? {
        guard text.hasPrefix("0x") else { return nil }
        var nibbles: [UInt8] = []
        for character in text.utf8.dropFirst(2) {
            switch character {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): nibbles.append(character - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): nibbles.append(character - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): nibbles.append(character - UInt8(ascii: "A") + 10)
            default: return nil
            }
        }
        let significant = Array(nibbles.drop { $0 == 0 })
        guard !nibbles.isEmpty, significant.count <= 64 else { return nil }
        let padded = [UInt8](repeating: 0, count: 64 - significant.count) + significant
        return stride(from: 0, to: 64, by: 2).map { padded[$0] << 4 | padded[$0 + 1] }
    }
}
