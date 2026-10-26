import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Checks the permanent JSON names of transaction records, so saved records stay readable.
///
/// Dates are seconds since 1 January 2001, as `JSONEncoder` writes them by default.
struct TransactionRecordTests {
    /// The account that sent every record.
    private static let account = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    /// The recipient of every payment.
    private static let recipient = "4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"
    /// The mint of every token payment.
    private static let mint = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"

    /// A settled token payment keeps its recipient, mint, and units beside its other facts.
    /// - Throws: A fixture or encoding error.
    @Test
    func `A settled token payment saves every fact under its permanent name`() throws {
        let record = try Self.record(.payment(recipient: Address(Self.recipient), mint: Address(Self.mint),
                                              units: 2_500_000),
                                     status: .succeeded, settled: 800_000_060)

        try #expect(Self.object(JSONEncoder().encode(record)) == Self.object("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", "kind": "payment",
             "recipient": "\(Self.recipient)", "mint": "\(Self.mint)", "units": 2500000, "signature": "signature",
             "lastValidBlockHeight": 550, "status": "succeeded", "created": 800000000, "settled": 800000060}
            """))
    }

    /// Private moves keep their lamports under their own kind's name, without a recipient.
    /// - Parameters:
    ///   - kind: The move.
    ///   - name: The move's persisted kind.
    /// - Throws: A fixture or encoding error.
    @Test(arguments: [(TransactionRecord.Kind.privateDeposit(lamports: 1_000), "privateDeposit"),
                      (.privateWithdrawal(lamports: 1_000), "privateWithdrawal")])
    func `A pending private move saves its lamports`(kind: TransactionRecord.Kind, name: String) throws {
        try #expect(Self.object(JSONEncoder().encode(Self.record(kind))) == Self.object("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", "kind": "\(name)",
             "lamports": 1000, "signature": "signature", "lastValidBlockHeight": 550, "status": "pending",
             "created": 800000000}
            """))
    }

    /// A key in the pending index keeps its account and network under their permanent names.
    /// - Throws: An encoding error.
    @Test
    func `A pending index key saves its account and network under their permanent names`() throws {
        let key = TransactionRecord.Key(account: Self.account, network: .devnet)

        try #expect(Self.object(JSONEncoder().encode(key)) == Self.object("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet"}
            """))
    }

    /// A saved pending SOL payment, which has no mint and no settled date, reads back as the same record.
    /// - Throws: A fixture or decoding error.
    @Test
    func `A saved SOL payment reads back`() throws {
        let saved = Data("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", "kind": "payment",
             "recipient": "\(Self.recipient)", "units": 1000000000, "signature": "signature",
             "lastValidBlockHeight": 550, "status": "pending", "created": 800000000}
            """.utf8)

        let record = try JSONDecoder().decode(TransactionRecord.self, from: saved)

        #expect(try record == Self.record(.payment(recipient: Address(Self.recipient), mint: nil, units: 1_000_000_000)))
    }

    /// A kind that this version doesn't know can't be read, so it's never mistaken for another kind.
    @Test
    func `An unknown kind can't be read`() {
        let saved = Data("""
            {"account": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "network": "devnet", "kind": "swap",
             "signature": "signature", "lastValidBlockHeight": 550, "status": "pending", "created": 800000000}
            """.utf8)

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(TransactionRecord.self, from: saved) }
    }

    /// Creates a devnet record sent at 800,000,000 seconds after 1 January 2001.
    /// - Parameters:
    ///   - kind: What the transaction does.
    ///   - status: Whether it settled, and how.
    ///   - settled: When it settled, in seconds after 1 January 2001, or `nil` while it's pending.
    /// - Returns: The record.
    private static func record(_ kind: TransactionRecord.Kind, status: TransactionRecord.Status = .pending,
                               settled: TimeInterval? = nil) -> TransactionRecord {
        .fixture(kind, account: account, status: status, created: 800_000_000, settled: settled)
    }

    /// Reads JSON as an object whose key order doesn't matter.
    /// - Parameter data: The JSON.
    /// - Returns: The JSON object.
    /// - Throws: A JSON error.
    private static func object(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    /// Reads JSON text as an object whose key order doesn't matter.
    /// - Parameter text: The JSON text.
    /// - Returns: The JSON object.
    /// - Throws: A JSON error.
    private static func object(_ text: String) throws -> NSDictionary {
        try object(Data(text.utf8))
    }
}
