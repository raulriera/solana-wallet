import Encoding
import Foundation

/// The validated program, bytes, and extensions of a token account or mint.
struct TokenData: Sendable {
    let program: TokenProgram
    let bytes: [UInt8]
    let extensions: [UInt16: [UInt8]]

    /// Creates token data by reading the account's program and validating its layout and extensions.
    ///
    /// - Parameters:
    ///   - data: The account's raw bytes.
    ///   - programAddress: The account's owner program.
    ///   - isMint: Whether the account is a mint rather than a token account.
    /// - Throws: ``TokenError/unsupportedProgram`` for an owner that isn't a token program, or
    ///   ``TokenError/invalidAccount`` for malformed framing.
    init(_ data: Data, programAddress: Address, isMint: Bool) throws {
        guard let program = TokenProgram(rawValue: programAddress.value) else { throw TokenError.unsupportedProgram }
        self.program = program
        bytes = Array(data)
        let baseSize = isMint ? 82 : 165
        guard bytes.count >= baseSize, bytes.count != 355 else { throw TokenError.invalidAccount }
        if bytes.count == baseSize { extensions = [:]; return }
        guard program == .token2022, bytes.count >= 166,
              bytes[165] == (isMint ? 1 : 2),
              bytes[baseSize..<165].allSatisfy({ $0 == 0 }) else { throw TokenError.invalidAccount }
        var values: [UInt16: [UInt8]] = [:]
        var reader = ByteReader(bytes, at: 166, error: TokenError.invalidAccount)
        while bytes[reader.offset...].contains(where: { $0 != 0 }) {
            let type: UInt16 = try reader.integer()
            let length: UInt16 = try reader.integer()
            guard type != 0, values[type] == nil else { throw TokenError.invalidAccount }
            values[type] = Array(try reader.read(count: Int(length)))
        }
        extensions = values
    }

    /// Reads an unsigned little-endian integer.
    ///
    /// - Parameters:
    ///   - bytes: The bytes that hold the field.
    ///   - offset: The field's position.
    /// - Returns: The integer.
    /// - Throws: ``TokenError/invalidAccount`` if the field is truncated.
    static func integer<Value: FixedWidthInteger & UnsignedInteger>(_ bytes: [UInt8], at offset: Int) throws -> Value {
        var reader = ByteReader(bytes, at: offset, error: TokenError.invalidAccount)
        return try reader.integer()
    }

    /// Checks that an optional field's tag is zero or one.
    ///
    /// - Parameter offset: The tag's position in the base layout.
    /// - Throws: ``TokenError/invalidAccount`` for another tag.
    func validateOption(at offset: Int) throws {
        let tag: UInt32 = try Self.integer(bytes, at: offset)
        guard tag <= 1 else { throw TokenError.invalidAccount }
    }

    /// Returns an extension's bytes after checking their length.
    ///
    /// - Parameters:
    ///   - type: The extension's type number.
    ///   - length: The expected byte count.
    /// - Returns: The extension bytes, or `nil` when absent.
    /// - Throws: ``TokenError/invalidAccount`` for an incorrect length.
    func value(_ type: UInt16, length: Int) throws -> [UInt8]? {
        guard let value = extensions[type] else { return nil }
        guard value.count == length else { throw TokenError.invalidAccount }
        return value
    }
}
