import Foundation

nonisolated enum AccountReplies {
    static func account(owner: String, lamports: UInt64 = 1, data: [UInt8] = []) -> String {
        """
        {"owner":"\(owner)","lamports":\(lamports),"executable":false,\
        "data":["\(Data(data).base64EncodedString())","base64"]}
        """
    }

    static func accounts(_ accounts: [String?]) -> String {
        #"{"context":{"slot":7},"value":[\#(accounts.map { $0 ?? "null" }.joined(separator: ","))]}"#
    }
}

func reply(to request: URLRequest, accounts: [String?]) throws -> (Data, URLResponse) {
    try reply(to: request, payload: #""result":\#(AccountReplies.accounts(accounts))"#)
}

extension StubTransport {
    static func replying(accounts: [String?]) -> StubTransport {
        StubTransport { request in try reply(to: request, accounts: accounts) }
    }
}
