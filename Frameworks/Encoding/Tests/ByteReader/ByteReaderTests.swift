import Testing
@testable import Encoding

struct ByteReaderTests {
    private enum ReadError: Error { case truncated }

    @Test
    func `Reads start at the offset and continue in order`() throws {
        var reader = ByteReader([0xff, 0x34, 0x12, 0x78, 0x56, 0xaa], at: 1, error: ReadError.truncated)

        let first: UInt16 = try reader.integer()
        let second: UInt16 = try reader.integer()

        #expect(first == 0x1234)
        #expect(second == 0x5678)
        #expect(try reader.read(count: 1) == [0xaa])
        #expect(reader.offset == 6)
        #expect(reader.isAtEnd)
    }

    @Test(arguments: [2, 4, -1])
    func `Reads past either end throw the reader's error`(offset: Int) {
        var reader = ByteReader([0x01, 0x02, 0x03, 0x04], at: offset, error: ReadError.truncated)

        #expect(throws: ReadError.truncated) { try reader.integer() as UInt32 }
        #expect(reader.offset == offset)
    }

    @Test
    func `The next byte is seen without being read`() throws {
        var reader = ByteReader([0x01, 0x02], error: ReadError.truncated)

        #expect(reader.nextByte == 0x01)
        #expect(reader.offset == 0)
        #expect(!reader.isAtEnd)
        _ = try reader.read(count: 2)
        #expect(reader.nextByte == nil)
    }

    @Test
    func `No next byte is seen before the input`() {
        let reader = ByteReader([0x01, 0x02], at: -1, error: ReadError.truncated)

        #expect(reader.nextByte == nil)
    }
}
