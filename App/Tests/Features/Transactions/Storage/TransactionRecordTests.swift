import Foundation
import RPC
import Testing
@testable import widgets

struct TransactionRecordTests {
    private static let account = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    @Test(arguments: [(TransactionRecord.Kind.payment, "payment"), (.privateDeposit, "privateDeposit"),
                      (.privateWithdrawal, "privateWithdrawal")])
    func `A record saves the facts that find its transaction again, and is read as pending`(
        kind: TransactionRecord.Kind, name: String
    ) throws {
        let settled = TransactionRecord.fixture(kind, account: Self.account, status: .succeeded, settled: 800_000_060)

        let data = try JSONEncoder().encode(settled)

        try #expect(Self.object(data) == Self.object(Data("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", "kind": "\(name)",
             "signature": "signature", "lastValidBlockHeight": 550}
            """.utf8)))
        #expect(try JSONDecoder().decode(TransactionRecord.self, from: data) == .fixture(kind, account: Self.account))
    }

    private static func object(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}
