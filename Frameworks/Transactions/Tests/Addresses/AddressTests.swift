import Foundation
import Testing
import Transactions

struct AddressTests {
    private static let malformedAddresses: [String] = [
        "9WzDXwBbmkg8ZTbNMqUxvQRАyrZzDsGYdLVL9zYtAWWM",
        String(repeating: "1", count: 31),
        String(repeating: "1", count: 33),
    ]

    @Test(arguments: malformedAddresses)
    func `Addresses require strict Base58 and exactly 32 bytes`(_ value: String) {
        #expect(throws: ValidationError.invalidAddress) { try Address(value) }
    }

    @Test
    func `Addresses encode as their Base58 text and decode unchanged`() throws {
        let address = try Address("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        let data = try JSONEncoder().encode(address)
        #expect(String(decoding: data, as: UTF8.self) == #""9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM""#)
        #expect(try JSONDecoder().decode(Address.self, from: data) == address)
    }

    @Test(arguments: malformedAddresses)
    func `Decoding rejects text that isn't a valid address`(_ value: String) throws {
        let data = try JSONEncoder().encode(value)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Address.self, from: data) }
    }

    @Test(arguments: [(SignedTransferFixture.sender, true), (TokenFixtures.transfers[0].destination, false)])
    func `Curve checks tell signing keys from program-derived addresses`(address: String, onCurve: Bool) throws {
        #expect(try Address(address).isOnCurve == onCurve)
    }
}
