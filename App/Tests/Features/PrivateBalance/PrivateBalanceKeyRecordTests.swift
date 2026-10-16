import Foundation
import Privacy
import Testing
import Transactions
@testable import widgets

/// Verifies how this device keeps an account's private-balance keys: their JSON round trip, the rejection of unusable
/// keys, and redaction.
struct PrivateBalanceKeyRecordTests {
    /// Kept keys decode to the same record, which pairs with the account's address.
    @Test
    func `Kept keys round trip and pair with the account's address`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)

        let decoded = try JSONDecoder().decode(PrivateBalanceKeyRecord.self, from: JSONEncoder().encode(record))

        #expect(decoded == record)
        #expect(try decoded.shieldedAccount(for: account.address).signingAddress == account.address)
    }

    /// A nullifier secret that isn't 31 bytes, or a viewing key that isn't a P-256 scalar, doesn't decode.
    /// - Parameters:
    ///   - nullifierSecret: The kept nullifier secret's length.
    ///   - viewingKey: The kept viewing key's bytes.
    @Test(arguments: [
        (30, [UInt8](repeating: 1, count: 32)),
        (32, [UInt8](repeating: 1, count: 32)),
        (31, [UInt8](repeating: 0, count: 32)),
        (31, [UInt8](repeating: 1, count: 31)),
    ])
    func `Unusable keys don't decode`(nullifierSecret: Int, viewingKey: [UInt8]) throws {
        let json = try JSONEncoder().encode([
            "nullifierSecret": Data(repeating: 1, count: nullifierSecret),
            "viewingKey": Data(viewingKey),
        ])

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PrivateBalanceKeyRecord.self, from: json) }
    }

    /// Descriptions and reflection never show the keys.
    @Test
    func `Descriptions omit the keys`() async throws {
        let record = try await PrivateBalanceFixtures.keys(for: PrivateBalanceFixtures.account())

        #expect(String(describing: record) == "PrivateBalanceKeyRecord")
        #expect(String(reflecting: record) == "PrivateBalanceKeyRecord")
        #expect(Mirror(reflecting: record).children.isEmpty)
    }
}
