import Algorithms
import Foundation
import Testing
@testable import RPC

nonisolated enum PageCursor {
    static func cursor(forPage page: Int) -> String {
        Data("page \(page)".utf8).base64EncodedString()
    }

    static func page(of cursor: String?) throws -> Int {
        guard let cursor else { return 0 }
        let text = String(decoding: try #require(Data(base64Encoded: cursor)), as: UTF8.self)
        try #require(text.hasPrefix("page "))
        return try #require(Int(text.dropFirst("page ".count)))
    }

    static func page(of request: URLRequest) throws -> Int {
        let params = try #require(try requestBody(request)["params"] as? [String: Any])
        return try page(of: params["paginationToken"] as? String)
    }

    static func pages<Row>(of rows: [Row], perPage: Int?) -> [(rows: [Row], next: String?)] {
        guard let perPage, rows.count > perPage else { return [(rows, nil)] }
        let pages = rows.chunks(ofCount: perPage).map(Array.init)
        return pages.enumerated().map { number, page in
            (page, number < pages.count - 1 ? cursor(forPage: number + 1) : nil)
        }
    }
}
