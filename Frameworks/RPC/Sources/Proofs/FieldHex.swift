/// The prover's hexadecimal text for 32-byte big-endian values, such as BN254 field elements.
///
/// Requests use `0x` and lowercase digits without leading zeros, so zero is `0x0`. Responses may pad
/// values to 64 digits.
enum FieldHex {
    /// The lowercase hexadecimal digits.
    private static let digits = Array("0123456789abcdef".utf8)

    /// Encodes big-endian bytes as `0x` and lowercase digits without leading zeros.
    ///
    /// - Parameter bytes: The big-endian value.
    /// - Returns: The value's text, `0x0` for zero.
    static func encode(_ bytes: [UInt8]) -> String {
        let nibbles = bytes.flatMap { [$0 >> 4, $0 & 0x0f] }.drop { $0 == 0 }
        let text = nibbles.isEmpty ? [digits[0]] : nibbles.map { digits[Int($0)] }
        return "0x" + String(decoding: text, as: UTF8.self)
    }

    /// Encodes an integer as `0x` and lowercase digits without leading zeros.
    ///
    /// - Parameter value: The integer, such as a tree ID or a flag.
    /// - Returns: The value's text, `0x0` for zero.
    static func encode(integer value: UInt64) -> String {
        "0x" + String(value, radix: 16)
    }

    /// Decodes `0x` and one or more hexadecimal digits, with or without leading zeros, as 32 big-endian bytes.
    ///
    /// - Parameter text: The value's text.
    /// - Returns: The value right-aligned in 32 bytes, or `nil` without the prefix, for other characters,
    ///   or for a value of more than 32 bytes.
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
