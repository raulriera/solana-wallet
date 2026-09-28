import Foundation

/// Reads token base layouts and extension framing without trusting RPC parser output.
struct TokenData: Sendable {
    let bytes: [UInt8]
    let extensions: [UInt16: [UInt8]]

    /// Validates base size, account type, padding, and unique bounded TLV entries.
    ///
    /// - Parameters:
    ///   - data: Raw account bytes from RPC, including any extension data.
    ///   - program: The verified account owner program.
    ///   - isMint: Whether the base layout is a mint rather than a token account.
    /// - Throws: ``TokenError/invalidAccount`` for malformed framing.
    init(_ data: Data, program: TokenProgram, isMint: Bool) throws {
        bytes = Array(data)
        let baseSize = isMint ? 82 : 165
        guard bytes.count >= baseSize, bytes.count != 355 else { throw TokenError.invalidAccount }
        if bytes.count == baseSize { extensions = [:]; return }
        guard program == .token2022, bytes.count >= 166,
              bytes[165] == (isMint ? 1 : 2),
              bytes[baseSize..<165].allSatisfy({ $0 == 0 }) else { throw TokenError.invalidAccount }
        var values: [UInt16: [UInt8]] = [:]
        var offset = 166
        while offset < bytes.count {
            if bytes[offset...].allSatisfy({ $0 == 0 }) { break }
            guard bytes.count - offset >= 4 else { throw TokenError.invalidAccount }
            let type = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
            let length = Int(bytes[offset + 2]) | Int(bytes[offset + 3]) << 8
            offset += 4
            guard type != 0, values[type] == nil, length <= bytes.count - offset else {
                throw TokenError.invalidAccount
            }
            values[type] = Array(bytes[offset..<(offset + length)])
            offset += length
        }
        extensions = values
    }

    /// Reads a bounded unsigned little-endian integer.
    ///
    /// - Parameters:
    ///   - bytes: The validated field's containing bytes.
    ///   - offset: The field's zero-based position.
    /// - Returns: The exact integer without floating-point conversion.
    /// - Throws: ``TokenError/invalidAccount`` if the field is truncated.
    static func integer<Value: FixedWidthInteger & UnsignedInteger>(_ bytes: [UInt8], at offset: Int) throws -> Value {
        let count = Value.bitWidth / 8
        guard offset >= 0, offset <= bytes.count, count <= bytes.count - offset else {
            throw TokenError.invalidAccount
        }
        return bytes[offset..<(offset + count)].enumerated().reduce(Value.zero) {
            $0 | (Value($1.element) << ($1.offset * 8))
        }
    }

    /// Checks a Rust COption discriminant while leaving its payload uninterpreted.
    ///
    /// - Parameter offset: The discriminant's position in the base layout.
    /// - Throws: ``TokenError/invalidAccount`` for a discriminant other than zero or one.
    func validateOption(at offset: Int) throws {
        let tag: UInt32 = try Self.integer(bytes, at: offset)
        guard tag <= 1 else { throw TokenError.invalidAccount }
    }

    /// Requires an extension's exact known length before interpreting it.
    ///
    /// - Parameters:
    ///   - type: The extension's numeric identifier.
    ///   - length: The expected byte count.
    /// - Returns: The extension bytes, or `nil` when absent.
    /// - Throws: ``TokenError/invalidAccount`` for an incorrect length.
    func value(_ type: UInt16, length: Int) throws -> [UInt8]? {
        guard let value = extensions[type] else { return nil }
        guard value.count == length else { throw TokenError.invalidAccount }
        return value
    }
}
