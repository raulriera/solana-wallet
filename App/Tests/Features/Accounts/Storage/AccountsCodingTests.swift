import Foundation
import Testing
import Transactions
import Wallet
@testable import widgets

/// Verifies the saved accounts' JSON format and that only valid, distinct accounts are read back.
struct AccountsCodingTests {
    /// Two accounts of one wallet in the format that earlier versions of the app wrote, with escaped slashes.
    private static let file = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","recoveryID":"0B6D2F4A-6C1E-4E8B-9A3D-5F7C1B2E8D90","address":"7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe","path":"m\/44'\/501'\/0'\/0'"},{"id":"1C4E7A2B-3D5F-4A6B-8C9D-0E1F2A3B4C5D","recoveryID":"0B6D2F4A-6C1E-4E8B-9A3D-5F7C1B2E8D90","address":"6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK","path":"m\/44'\/501'\/0'"}]"#

    /// The accounts that ``file`` keeps: both path families at the same index.
    private static var accounts: [widgets.Account] {
        get throws {
            let recoveryID = try #require(UUID(uuidString: "0B6D2F4A-6C1E-4E8B-9A3D-5F7C1B2E8D90"))
            return [
                widgets.Account(id: try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")),
                                recoveryID: recoveryID,
                                address: try Address("7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe"),
                                path: try DerivationPath("m/44'/501'/0'/0'")),
                widgets.Account(id: try #require(UUID(uuidString: "1C4E7A2B-3D5F-4A6B-8C9D-0E1F2A3B4C5D")),
                                recoveryID: recoveryID,
                                address: try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                                path: try DerivationPath("m/44'/501'/0'")),
            ]
        }
    }

    /// A file that earlier versions of the app wrote reads back as the same accounts, in order.
    @Test
    func `The existing file format decodes`() throws {
        #expect(AccountsCoding().decode(Data(Self.file.utf8)) == (try Self.accounts))
    }

    /// The accounts encode to the same fields and values earlier versions of the app wrote; JSON leaves key order open.
    @Test
    func `Accounts encode to the existing file format`() throws {
        let encoded = try #require(JSONSerialization.jsonObject(with: AccountsCoding().encode(Self.accounts))
            as? [[String: String]])
        let existing = try #require(JSONSerialization.jsonObject(with: Data(Self.file.utf8)) as? [[String: String]])

        #expect(encoded == existing)
    }

    /// A custom name is saved with the account and read back, beside an account that keeps its numbered name.
    @Test
    func `Custom names are saved and read back`() throws {
        var accounts = try Self.accounts
        accounts[0].customName = "Savings"

        let encoded = try AccountsCoding().encode(accounts)
        let records = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: String]])

        #expect(AccountsCoding().decode(encoded) == accounts)
        #expect(records.map { $0["name"] } == ["Savings", nil])
    }

    /// An empty list is a value, unlike missing bytes.
    @Test
    func `An empty list decodes`() {
        #expect(AccountsCoding().decode(Data("[]".utf8)) == [])
    }

    /// Bytes that aren't a list of valid accounts aren't a value, so the file that keeps them is never replaced.
    /// - Parameter file: The kept bytes.
    @Test(arguments: [
        "not-json",
        #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF"}"#,
        #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","address":"7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe","path":"m\/44'\/501'\/0'\/0'"}]"#,
        #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","recoveryID":"0B6D2F4A-6C1E-4E8B-9A3D-5F7C1B2E8D90","address":"invalid","path":"m\/44'\/501'\/0'\/0'"}]"#,
        #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","recoveryID":"0B6D2F4A-6C1E-4E8B-9A3D-5F7C1B2E8D90","address":"7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe","path":"m\/44'\/501'\/2147483648'"}]"#,
    ])
    func `Malformed accounts are unreadable`(_ file: String) {
        #expect(AccountsCoding().decode(Data(file.utf8)) == nil)
    }

    /// A list that saves one account twice is unreadable; the store's tests cover each kind of duplicate.
    @Test
    func `Duplicate accounts are unreadable`() throws {
        let first = try Self.accounts[0]
        let other = try Self.accounts[1]
        let duplicate = widgets.Account(id: UUID(), recoveryID: UUID(), address: first.address, path: other.path)
        // Encoding doesn't check for duplicates, so it writes the list a damaged file could keep.
        let file = try AccountsCoding().encode([first, duplicate])

        #expect(AccountsCoding().decode(file) == nil)
    }
}
