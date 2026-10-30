/// A Base58 encoder and decoder that uses the Bitcoin alphabet.
public enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    /// Encodes bytes as Base58 text.
    ///
    /// - Parameter bytes: The bytes to encode.
    /// - Returns: The Base58 text, without a checksum.
    public static func encode(_ bytes: [UInt8]) -> String {
        let leadingZeros = bytes.prefix(while: { $0 == 0 }).count
        var digits: [Int] = []
        for byte in bytes.dropFirst(leadingZeros) {
            var carry = Int(byte)
            for index in digits.indices {
                carry += digits[index] * 256
                digits[index] = carry % 58
                carry /= 58
            }
            while carry > 0 {
                digits.append(carry % 58)
                carry /= 58
            }
        }
        let encoded = [UInt8](repeating: alphabet[0], count: leadingZeros) + digits.reversed().map { alphabet[$0] }
        return String(decoding: encoded, as: UTF8.self)
    }

    /// Decodes Base58 text into a fixed number of bytes.
    ///
    /// - Parameters:
    ///   - value: The Base58 text.
    ///   - byteCount: The number of bytes to decode.
    /// - Returns: Exactly `byteCount` bytes, or `nil` for malformed text or a width mismatch.
    public static func decode(_ value: String, byteCount: Int) -> [UInt8]? {
        guard byteCount >= 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        var leadingZeros = 0
        var hasSignificantDigit = false

        for character in value.utf8 {
            guard let digit = alphabet.firstIndex(of: character) else { return nil }
            if !hasSignificantDigit && digit == 0 {
                guard leadingZeros < byteCount else { return nil }
                leadingZeros += 1
                continue
            }
            hasSignificantDigit = true
            var carry = digit
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 0xff)
                carry >>= 8
            }
            guard carry == 0 else { return nil }
        }

        let significantBytes = bytes.lastIndex(where: { $0 != 0 }).map { $0 + 1 } ?? 0
        guard significantBytes == byteCount - leadingZeros else { return nil }
        return Array(bytes.reversed())
    }
}
