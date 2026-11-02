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
