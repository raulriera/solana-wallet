@testable import Privacy
import Testing

/// Verifies the little-endian integers of Solana Rings payloads.
struct LittleEndianBytesTests {
    /// Verifies that appending writes the least significant byte first, at the integer's width.
    @Test
    func `Appending writes the least significant byte first`() {
        var bytes: [UInt8] = [0xaa]

        bytes.appendLittleEndian(UInt32(0x0102_0304))
        bytes.appendLittleEndian(UInt64(0x0102_0304_0506_0708))

        #expect(bytes == [0xaa, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1])
    }

    /// Verifies that reading at an offset returns the integer whose least significant byte is first.
    @Test
    func `Reading at an offset returns the integer`() {
        let bytes: [UInt8] = [0xaa, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1]

        #expect(bytes.littleEndian(at: 1) == UInt32(0x0102_0304))
        #expect(bytes.littleEndian(at: 5) == UInt64(0x0102_0304_0506_0708))
    }
}
