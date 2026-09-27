import Foundation

extension Data {
    /// Appends an integer using its fixed-width little-endian representation.
    ///
    /// - Parameter value: The integer to encode without padding or a length prefix.
    mutating func appendLittleEndian<Integer: FixedWidthInteger>(_ value: Integer) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
