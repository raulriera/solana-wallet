import Foundation
import Storage
import Testing

/// Checks that values kept as JSON come back unchanged, and that other bytes are refused.
struct JSONCodingTests {
    /// A saved value, including a URL, comes back as it was saved.
    /// - Throws: An encoding or test prerequisite error.
    @Test
    func `A value comes back as it was saved`() throws {
        let link = try #require(URL(string: "https://rpc.example.com/fixture-token?api-key=fixture-key"))
        let bookmark = Bookmark(title: "Example", link: link)
        let coding: JSONCoding<Bookmark> = .json(Bookmark.self)

        #expect(coding.decode(try coding.encode(bookmark)) == bookmark)
    }

    /// Bytes that aren't JSON for the type decode to nothing instead of a default value.
    @Test
    func `Bytes that aren't the value decode to nothing`() {
        #expect(JSONCoding<Bookmark>().decode(Data("not a bookmark".utf8)) == nil)
    }
}

/// A small saved value with text and a URL.
private struct Bookmark: Codable, Equatable {
    /// The bookmark's name.
    let title: String
    /// The bookmarked page.
    let link: URL
}
