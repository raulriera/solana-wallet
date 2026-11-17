import Foundation
import Storage
import Testing

struct JSONCodingTests {
    @Test
    func `Bytes that aren't the value decode to nothing`() {
        #expect(JSONCoding<Bookmark>().decode(Data("not a bookmark".utf8)) == nil)
    }
}

private struct Bookmark: Codable, Equatable {
    let title: String
    let link: URL
}
