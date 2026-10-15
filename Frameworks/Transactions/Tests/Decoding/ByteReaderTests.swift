import Foundation
import Testing
@testable import Transactions

/// Verifies bounded little-endian reads from any start position.
struct ByteReaderTests {
    /// Verifies that reads start at the given offset and continue where the previous read ended.
    /// - Throws: An error if a read runs past the end of the input.
    @Test
    func `Reads start at the offset and continue in order`() throws {
        var reader = ByteReader([0xff, 0x34, 0x12, 0x78, 0x56, 0xaa], at: 1, error: TokenError.invalidAccount)

        let first: UInt16 = try reader.integer()
        let second: UInt16 = try reader.integer()

        #expect(first == 0x1234)
        #expect(second == 0x5678)
        #expect(try reader.read(count: 1) == Data([0xaa]))
        #expect(reader.offset == 6)
    }

    /// Verifies that a read the input can't complete throws the reader's error and consumes nothing.
    ///
    /// - Parameter offset: A start position too close to the end, past the end, or before the start.
    @Test(arguments: [2, 4, -1])
    func `Reads past either end throw the reader's error`(offset: Int) {
        var reader = ByteReader([0x01, 0x02, 0x03, 0x04], at: offset, error: TokenError.invalidAccount)

        #expect(throws: TokenError.invalidAccount) { try reader.integer() as UInt32 }
        #expect(reader.offset == offset)
    }
}
