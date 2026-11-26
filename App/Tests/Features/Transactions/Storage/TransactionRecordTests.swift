import Foundation
import Testing
@testable import widgets

struct TransactionRecordTests {
    private static let account = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    private static let transaction = "gQEAAR8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEDMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2B+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAiBMAAAAAAAAgTgAAAAABAAAAAQACAgwAAAECAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

    @Test(arguments: [(TransactionRecord.Kind.payment, "payment"), (.privatePayment, "privatePayment"),
                      (.privateDeposit, "privateDeposit"), (.privateWithdrawal, "privateWithdrawal")])
    func `A pending record saves its transaction and outcome`(kind: TransactionRecord.Kind, name: String) throws {
        let record = TransactionRecord.fixture(kind, account: Self.account)

        let data = try JSONEncoder().encode(record)

        #expect(try data.jsonObject() == Data("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "kind": "\(name)", "transaction": "\(Self.transaction)",
             "outcome": {"signature": "signature", "network": "devnet", "lastValidBlockHeight": 550,
                         "status": {"pending": {}}}}
            """.utf8).jsonObject())
        #expect(try JSONDecoder().decode(TransactionRecord.self, from: data) == record)
    }
}
