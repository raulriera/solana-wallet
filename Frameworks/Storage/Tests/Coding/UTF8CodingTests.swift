import Foundation
import Storage
import Testing

struct UTF8CodingTests {
    @Test
    func `Bytes that aren't UTF-8 decode to nothing`() {
        #expect(UTF8Coding().decode(Data([0xFF, 0xFE])) == nil)
    }
}
