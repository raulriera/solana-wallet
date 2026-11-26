import Foundation
import Testing
@testable import Transactions

struct SingleValueDecodingContainerParsingTests {
    @Test
    func `Text that parses decodes as the parsed value`() throws {
        #expect(try JSONDecoder().decode(Number.self, from: Data(#""42""#.utf8)).value == 42)
    }

    @Test
    func `Text that doesn't parse throws corrupted data with the description and the parse error`() {
        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Number.self, from: Data(#""forty-two""#.utf8))
        }

        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected corrupted data, not \(String(describing: error)).")
            return
        }
        #expect(context.debugDescription == "Invalid number.")
        #expect(context.underlyingError is Number.ParseError)
    }
}

private struct Number: Decodable {
    struct ParseError: Error {}

    let value: Int

    init(from decoder: any Decoder) throws {
        value = try decoder.singleValueContainer().decode(parsing: { text in
            guard let value = Int(text) else { throw ParseError() }
            return value
        }, debugDescription: "Invalid number.")
    }
}
