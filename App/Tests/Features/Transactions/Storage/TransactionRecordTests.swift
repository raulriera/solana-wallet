import Foundation
import RPC
import Testing
@testable import widgets

struct TransactionRecordTests {
    private static let account = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    @Test
    func `A settled payment saves every fact under its permanent name`() throws {
        let record = Self.record(.payment, status: .succeeded, settled: 800_000_060)

        try #expect(Self.object(JSONEncoder().encode(record)) == Self.object("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", "kind": "payment",
             "signature": "signature", "lastValidBlockHeight": 550, "status": "succeeded", "created": 800000000,
             "settled": 800000060}
            """))
    }

    @Test(arguments: [(TransactionRecord.Kind.privateDeposit, "privateDeposit"),
                      (.privateWithdrawal, "privateWithdrawal")])
    func `A pending private move saves its kind`(kind: TransactionRecord.Kind, name: String) throws {
        try #expect(Self.object(JSONEncoder().encode(Self.record(kind))) == Self.object("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", "kind": "\(name)",
             "signature": "signature", "lastValidBlockHeight": 550, "status": "pending",
             "created": 800000000}
            """))
    }

    @Test
    func `A pending index key saves its account and network under their permanent names`() throws {
        let key = TransactionRecord.Key(account: Self.account, network: .devnet)

        try #expect(Self.object(JSONEncoder().encode(key)) == Self.object("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet"}
            """))
    }

    private static func record(_ kind: TransactionRecord.Kind, status: TransactionRecord.Status = .pending,
                               settled: TimeInterval? = nil) -> TransactionRecord {
        .fixture(kind, account: account, status: status, created: 800_000_000, settled: settled)
    }

    private static func object(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private static func object(_ text: String) throws -> NSDictionary {
        try object(Data(text.utf8))
    }
}
