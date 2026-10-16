@testable import Privacy
import Testing

/// Verifies the wincode encoding of instruction data: integers, arrays, counts, and options.
struct WincodeWriterTests {
    /// Verifies that integers are written little-endian at their fixed width and arrays raw.
    @Test
    func `Integers are little-endian and arrays are raw`() {
        var writer = WincodeWriter()
        writer.append(UInt8(0x10))
        writer.append(UInt16(0x0201))
        writer.append(UInt64(0x0807_0605_0403_0201))
        writer.append(array: [0xaa, 0xbb])

        #expect(writer.bytes == [0x10, 0x01, 0x02, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0xaa, 0xbb])
    }

    /// Verifies counts and options: a one-byte count, 0 for none, and 1 with a 16-bit length for a
    /// byte vector.
    @Test
    func `Counts and options use one byte and vectors a 16-bit length`() throws {
        var writer = WincodeWriter()
        try writer.appendCount(255)
        writer.appendNone()
        try writer.appendSome(vector: [0xcc, 0xdd, 0xee])
        try writer.appendSome(vector: [])

        #expect(writer.bytes == [0xff, 0x00, 0x01, 0x03, 0x00, 0xcc, 0xdd, 0xee, 0x01, 0x00, 0x00])
    }

    /// Verifies that a vector of 65,535 bytes, the longest that a 16-bit length counts, is written.
    @Test
    func `The longest byte vector is written`() throws {
        var writer = WincodeWriter()
        try writer.appendSome(vector: [UInt8](repeating: 7, count: 65_535))

        #expect(writer.bytes.prefix(3) == [0x01, 0xff, 0xff])
        #expect(writer.bytes.count == 65_538)
    }

    /// Verifies that counts beyond 255 and negative counts are rejected.
    ///
    /// - Parameter count: A count that a byte can't hold.
    @Test(arguments: [256, -1])
    func `Counts beyond a byte are rejected`(count: Int) {
        var writer = WincodeWriter()

        #expect(throws: WincodeWriter.ValidationError.lengthOverflow) { try writer.appendCount(count) }
        #expect(writer.bytes.isEmpty)
    }

    /// Verifies that a byte vector beyond 65,535 bytes is rejected without writing the option tag.
    @Test
    func `Byte vectors beyond a 16-bit length are rejected`() {
        var writer = WincodeWriter()

        #expect(throws: WincodeWriter.ValidationError.lengthOverflow) {
            try writer.appendSome(vector: [UInt8](repeating: 0, count: 65_536))
        }
        #expect(writer.bytes.isEmpty)
    }
}
