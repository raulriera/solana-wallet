import Testing
@testable import Privacy

struct WincodeReaderTests {
    private enum ReadError: Error { case malformed }

    @Test
    func `Integers are little-endian and arrays are raw`() throws {
        var reader = WincodeReader([0xff, 0x10, 0x01, 0x02, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0xaa, 0xbb], at: 1,
                                   error: ReadError.malformed)

        let byte: UInt8 = try reader.integer()
        let short: UInt16 = try reader.integer()
        let long: UInt64 = try reader.integer()

        #expect(byte == 0x10)
        #expect(short == 0x0201)
        #expect(long == 0x0807_0605_0403_0201)
        #expect(try reader.array(count: 2) == [0xaa, 0xbb])
        #expect(reader.isAtEnd)
    }

    @Test
    func `Counts and options use one byte and vectors a 16-bit length`() throws {
        var reader = WincodeReader([0xff, 0x00, 0x01, 0x03, 0x00, 0xcc, 0xdd, 0xee, 0x01, 0x00, 0x00, 0x2a],
                                   error: ReadError.malformed)

        #expect(try reader.count() == 255)
        #expect(try !reader.isPresent())
        #expect(try reader.isPresent())
        try reader.skipVector()
        #expect(try reader.isPresent())
        try reader.skipVector()
        try reader.skip(1)
        #expect(reader.isAtEnd)
    }

    @Test(arguments: [2, 0xff] as [UInt8])
    func `Option bytes other than 0 or 1 throw the reader's error`(byte: UInt8) {
        var reader = WincodeReader([byte], error: ReadError.malformed)

        #expect(throws: ReadError.malformed) { try reader.isPresent() }
    }

    @Test
    func `Reads past the end throw the reader's error`() {
        var vector = WincodeReader([0x03, 0x00, 0xcc, 0xdd], error: ReadError.malformed)
        var array = WincodeReader([0xaa], error: ReadError.malformed)
        var empty = WincodeReader([], error: ReadError.malformed)

        #expect(throws: ReadError.malformed) { try vector.skipVector() }
        #expect(throws: ReadError.malformed) { try array.array(count: 2) }
        #expect(throws: ReadError.malformed) { try array.skip(2) }
        #expect(throws: ReadError.malformed) { try empty.count() }
        #expect(throws: ReadError.malformed) { try empty.isPresent() }
        #expect(throws: ReadError.malformed) { try empty.integer() as UInt16 }
    }
}
