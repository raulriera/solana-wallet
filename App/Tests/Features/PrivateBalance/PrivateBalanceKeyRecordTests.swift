import Foundation
import Privacy
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

/// Verifies how this device keeps an account's private-balance keys: their JSON round trip, the rejection of unusable
/// keys, the one-time accounts of their code root, and redaction.
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

    /// A nullifier secret that isn't 31 bytes, a viewing key that isn't a P-256 scalar, or a code root that isn't 32
    /// bytes or is missing, as in a record kept before code roots, doesn't decode.
    /// - Parameters:
    ///   - nullifierSecret: The kept nullifier secret's length.
    ///   - viewingKey: The kept viewing key's bytes.
    ///   - codeRoot: The kept code root's length, or `nil` for none.
    @Test(arguments: [
        (30, [UInt8](repeating: 1, count: 32), Optional(32)),
        (32, [UInt8](repeating: 1, count: 32), 32),
        (31, [UInt8](repeating: 0, count: 32), 32),
        (31, [UInt8](repeating: 1, count: 31), 32),
        (31, [UInt8](repeating: 1, count: 32), 31),
        (31, [UInt8](repeating: 1, count: 32), nil),
    ])
    func `Unusable keys don't decode`(nullifierSecret: Int, viewingKey: [UInt8], codeRoot: Int?) throws {
        var fields = ["nullifierSecret": Data(repeating: 1, count: nullifierSecret), "viewingKey": Data(viewingKey)]
        fields["codeRoot"] = codeRoot.map { Data(repeating: 1, count: $0) }
        let json = try JSONEncoder().encode(fields)

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PrivateBalanceKeyRecord.self, from: json) }
    }

    /// Kept keys derive the same one-time accounts as Wallet's code root does.
    @Test
    func `Kept keys derive the account's one-time accounts`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let recovery = try PrivateBalanceFixtures.recovery()
        let keys = try await Wallet().privateBalanceKeys(using: recovery.phrase, expectedAddress: account.address.value,
                                                         passphrase: recovery.passphrase, path: account.path)

        let oneTime = try PrivateBalanceKeyRecord(keys).oneTimeAccount(at: 3)

        #expect(oneTime.address == (try OneTimeAccount(codeRoot: keys.codeRoot, index: 3)).address)
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
