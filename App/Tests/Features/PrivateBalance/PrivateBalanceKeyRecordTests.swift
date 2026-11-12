import Foundation
import Privacy
import Storage
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

struct PrivateBalanceKeyRecordTests {
    @Test
    func `Kept keys round trip and pair with the account's address`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)

        let decoded = try JSONDecoder().decode(PrivateBalanceKeyRecord.self, from: JSONEncoder().encode(record))

        #expect(decoded == record)
        #expect(try decoded.shieldedAccount(for: account.address).signingAddress == account.address)
    }

    @Test(arguments: [
        (30, 32, Optional(32)),
        (32, 32, 32),
        (31, 31, 32),
        (31, 33, 32),
        (31, 32, 31),
        (31, 32, nil),
    ])
    func `Unusable keys don't decode`(nullifierSecret: Int, viewingSecret: Int, codeRoot: Int?) throws {
        var fields = ["nullifierSecret": Data(repeating: 1, count: nullifierSecret),
                      "viewingSecret": Data(repeating: 1, count: viewingSecret)]
        fields["codeRoot"] = codeRoot.map { Data(repeating: 1, count: $0) }
        let json = try JSONEncoder().encode(fields)

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PrivateBalanceKeyRecord.self, from: json) }
    }

    @Test
    func `Keys kept with a P-256 viewing key are unreadable`() throws {
        let record = [
            "nullifierSecret": Data(repeating: 1, count: 31), "viewingKey": Data(repeating: 1, count: 32),
            "codeRoot": Data(repeating: 1, count: 32),
        ]
        let coding: JSONCoding<PrivateBalances.Keys> = .json(PrivateBalances.Keys.self)

        let kept = coding.decode(try JSONEncoder().encode(["account": record]))

        #expect(kept == nil)
    }

    @Test
    func `Kept keys derive the account's one-time accounts`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let recovery = try PrivateBalanceFixtures.recovery()
        let keys = try await Wallet().privateBalanceKeys(using: recovery.phrase, expectedAddress: account.address.value,
                                                         passphrase: recovery.passphrase, path: account.path)

        let oneTime = try PrivateBalanceKeyRecord(keys).oneTimeAccount(at: 3)

        #expect(oneTime.address == (try OneTimeAccount(codeRoot: keys.codeRoot, index: 3)).address)
    }
}
