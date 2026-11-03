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
        guard let bytes = decode(value, maximumCount: byteCount), bytes.count == byteCount else { return nil }
        return bytes
    }

    /// Decodes Base58 text into as many bytes as it encodes, stopping once they exceed a limit.
    ///
    /// - Parameters:
    ///   - value: The Base58 text.
    ///   - maximumCount: The most bytes to decode.
    /// - Returns: The bytes, with one zero byte for each leading `1`, or `nil` for malformed text or more than
    ///   `maximumCount` bytes.
    public static func decode(_ value: String, maximumCount: Int) -> [UInt8]? {
        guard maximumCount >= 0 else { return nil }
        var littleEndian: [UInt8] = []
        var leadingZeros = 0
        for character in value.utf8 {
            guard let digit = alphabet.firstIndex(of: character) else { return nil }
            if littleEndian.isEmpty && digit == 0 {
                leadingZeros += 1
            } else {
                var carry = digit
                for index in littleEndian.indices {
                    carry += Int(littleEndian[index]) * 58
                    littleEndian[index] = UInt8(carry & 0xff)
                    carry >>= 8
                }
                while carry > 0 {
                    littleEndian.append(UInt8(carry & 0xff))
                    carry >>= 8
                }
            }
            guard leadingZeros + littleEndian.count <= maximumCount else { return nil }
        }
        return [UInt8](repeating: 0, count: leadingZeros) + littleEndian.reversed()
    }
}
