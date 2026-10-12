import Foundation
import Testing
@testable import widgets

/// Checks that bytes which aren't UTF-8 are refused instead of becoming text.
struct UTF8CodingTests {
    /// Bytes that aren't UTF-8 decode to nothing, so a damaged key is unreadable instead of a different key.
    @Test
    func `Bytes that aren't UTF-8 decode to nothing`() {
        #expect(UTF8Coding().decode(Data([0xFF, 0xFE])) == nil)
    }
}
