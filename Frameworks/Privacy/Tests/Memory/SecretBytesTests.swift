@testable import Privacy
import Testing

/// Verifies the erasure of buffers that held secrets.
struct SecretBytesTests {
    /// Verifies that erasing a buffer zeroes every byte and keeps its length.
    ///
    /// - Parameter bytes: A buffer: empty, one byte, or every byte value.
    @Test(arguments: [[], [0xff], Array(UInt8.min...UInt8.max)] as [[UInt8]])
    func `Erasing zeroes every byte`(bytes: [UInt8]) {
        var erased = bytes

        erased.erase()

        #expect(erased == [UInt8](repeating: 0, count: bytes.count))
    }
}
