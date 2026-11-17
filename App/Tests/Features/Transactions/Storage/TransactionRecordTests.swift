import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

struct TransactionRecordTests {
    private static let account = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    private static let recipient = "4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"
    private static let mint = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"

    @Test
    func `A settled token payment saves every fact under its permanent name`() throws {
        let record = try Self.record(.payment(recipient: Address(Self.recipient),
                                              asset: .token(mint: Address(Self.mint)), amount: 2_500_000),
                                     status: .succeeded, settled: 800_000_060)

        try #expect(Self.object(JSONEncoder().encode(record)) == Self.object("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", "kind": "payment",
             "recipient": "\(Self.recipient)", "asset": {"token": {"mint": "\(Self.mint)"}}, "amount": 2500000, "signature": "signature",
             "lastValidBlockHeight": 550, "status": "succeeded", "created": 800000000, "settled": 800000060}
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

    @Test(arguments: [
        (Asset.ID.nativeSOL, #"{"nativeSOL": {}}"#, UInt64(1_000_000_000)),
        (try .token(mint: Address(Self.mint)), #"{"token": {"mint": "\#(Self.mint)"}}"#, 2_500_000),
    ])
    func `A saved payment reads back`(asset: Asset.ID, json: String, amount: UInt64) throws {
        let saved = Data("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", "kind": "payment",
             "recipient": "\(Self.recipient)", "asset": \(json), "amount": \(amount), "signature": "signature",
             "lastValidBlockHeight": 550, "status": "pending", "created": 800000000}
            """.utf8)

        let record = try JSONDecoder().decode(TransactionRecord.self, from: saved)

        #expect(try record == Self.record(.payment(recipient: Address(Self.recipient), asset: asset, amount: amount)))
    }

    @Test(arguments: [
        #""kind": "payment", "recipient": "\#(Self.recipient)", "amount": 1000000000"#,
        #""kind": "swap""#,
    ])
    func `A saved record without an asset or of an unknown kind can't be read`(fields: String) {
        let saved = Data("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", \(fields),
             "signature": "signature", "lastValidBlockHeight": 550, "status": "pending", "created": 800000000}
            """.utf8)

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(TransactionRecord.self, from: saved) }
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
