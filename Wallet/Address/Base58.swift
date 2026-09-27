/// Base58 encoding for Solana public keys.
enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    /// Encodes bytes while preserving each leading zero as `1`.
    ///
    /// - Parameter bytes: The bytes to encode in their original order.
    /// - Returns: The Base58 representation without a checksum.
    static func encode(_ bytes: [UInt8]) -> String {
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
}
