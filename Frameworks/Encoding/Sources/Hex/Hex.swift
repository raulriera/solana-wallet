/// A lowercase hexadecimal encoder and decoder.
public enum Hex {
    private static let digits = Array("0123456789abcdef".utf8)

    /// Encodes bytes as lowercase hexadecimal text.
    ///
    /// - Parameter bytes: The bytes to encode.
    /// - Returns: Two lowercase digits for each byte, or empty text for no bytes.
    public static func encode(_ bytes: [UInt8]) -> String {
        var encoded: [UInt8] = []
        encoded.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            encoded.append(digits[Int(byte >> 4)])
            encoded.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    /// Decodes lowercase hexadecimal text into bytes.
    ///
    /// - Parameter text: The lowercase hexadecimal text.
    /// - Returns: One byte for each pair of digits, or `nil` for an odd number of digits or a character other than
    ///   `0`–`9` and `a`–`f`.
    public static func decode(_ text: String) -> [UInt8]? {
        let characters = text.utf8
        guard characters.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(characters.count / 2)
        var iterator = characters.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            guard let high = value(of: high), let low = value(of: low) else { return nil }
            bytes.append(high << 4 | low)
        }
        return bytes
    }

    /// Returns the value of one lowercase hexadecimal digit.
    ///
    /// - Parameter digit: The digit's UTF-8 code unit.
    /// - Returns: The digit's value, or `nil` for a code unit other than `0`–`9` and `a`–`f`.
    private static func value(of digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
        default: nil
        }
    }
}
