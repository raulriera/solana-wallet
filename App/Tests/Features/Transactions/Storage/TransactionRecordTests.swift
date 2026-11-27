import Foundation
import Testing
@testable import widgets

struct TransactionRecordTests {
    private static let account = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    @Test(arguments: [(TransactionRecord.Kind.payment, "payment"), (.privatePayment, "privatePayment"),
                      (.privateDeposit, "privateDeposit"), (.privateWithdrawal, "privateWithdrawal")])
    func `A pending record saves its outcome`(kind: TransactionRecord.Kind, name: String) throws {
        let record = TransactionRecord.fixture(kind, account: Self.account)

        let data = try JSONEncoder().encode(record)

        #expect(try data.jsonObject() == Data("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "kind": "\(name)",
             "outcome": {"signature": "signature", "network": "devnet", "lastValidBlockHeight": 550,
                         "status": {"pending": {}}}}
            """.utf8).jsonObject())
        #expect(try JSONDecoder().decode(TransactionRecord.self, from: data) == record)
    }
}
