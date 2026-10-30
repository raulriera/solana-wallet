@testable import Privacy
import Testing

struct LittleEndianBytesTests {
    @Test
    func `Appending writes the least significant byte first`() {
        var bytes: [UInt8] = [0xaa]

        bytes.appendLittleEndian(UInt32(0x0102_0304))
        bytes.appendLittleEndian(UInt64(0x0102_0304_0506_0708))

        #expect(bytes == [0xaa, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1])
    }

    @Test
    func `Reading at an offset returns the integer`() {
        let bytes: [UInt8] = [0xaa, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1]

        #expect(bytes.littleEndian(at: 1) == UInt32(0x0102_0304))
        #expect(bytes.littleEndian(at: 5) == UInt64(0x0102_0304_0506_0708))
    }
}
