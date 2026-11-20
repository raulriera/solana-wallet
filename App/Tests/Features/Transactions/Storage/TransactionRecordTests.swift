import Foundation
import RPC
import Testing
@testable import widgets

struct TransactionRecordTests {
    private static let account = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    @Test(arguments: [(TransactionRecord.Kind.payment, "payment"), (.privatePayment, "privatePayment"),
                      (.privateDeposit, "privateDeposit"),
                      (.privateWithdrawal, "privateWithdrawal")])
    func `A record saves the facts that find its transaction again, and is read as pending`(
        kind: TransactionRecord.Kind, name: String
    ) throws {
        let settled = TransactionRecord.fixture(kind, account: Self.account, outcome: .succeeded)

        let data = try JSONEncoder().encode(settled)

        #expect(try data.jsonObject() == Data("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", "kind": "\(name)",
             "signature": "signature", "lastValidBlockHeight": 550}
            """.utf8).jsonObject())
        #expect(try JSONDecoder().decode(TransactionRecord.self, from: data) == .fixture(kind, account: Self.account))
    }
}
