import Foundation
import Storage
import Testing

struct JSONCodingTests {
    @Test
    func `A value comes back as it was saved`() throws {
        let link = try #require(URL(string: "https://rpc.example.com/fixture-token?api-key=fixture-key"))
        let bookmark = Bookmark(title: "Example", link: link)
        let coding: JSONCoding<Bookmark> = .json(Bookmark.self)

        #expect(coding.decode(try coding.encode(bookmark)) == bookmark)
    }

    @Test
    func `Bytes that aren't the value decode to nothing`() {
        #expect(JSONCoding<Bookmark>().decode(Data("not a bookmark".utf8)) == nil)
    }
}

private struct Bookmark: Codable, Equatable {
    let title: String
    let link: URL
}
