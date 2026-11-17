import Encoding
import Testing

struct RangeReplaceableCollectionIntegersTests {
    @Test
    func `Little-endian appends write the least significant byte first`() {
        var bytes: [UInt8] = [0xaa]

        bytes.append(littleEndian: UInt32(0x0102_0304))
        bytes.append(littleEndian: UInt64(0x0102_0304_0506_0708))

        #expect(bytes == [0xaa, 0x04, 0x03, 0x02, 0x01, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
    }

    @Test
    func `Big-endian appends write the most significant byte first`() {
        var bytes: [UInt8] = [0xaa]

        bytes.append(bigEndian: UInt32(0x0102_0304))
        bytes.append(bigEndian: UInt64(0x0102_0304_0506_0708))

        #expect(bytes == [0xaa, 0x01, 0x02, 0x03, 0x04, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
    }
}
