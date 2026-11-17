import Encoding
import Foundation
import Testing
@testable import Transactions

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

    @Test
    func `Addresses from bytes match the address parsed from their text`() throws {
        let text = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
        let bytes = try #require(Base58.decode(text, byteCount: 32))

        let address = try Address(bytes: bytes)

        #expect(address == (try Address(text)))
        #expect(address.value == text)
    }

    @Test(arguments: [0, 31, 33])
    func `Addresses from bytes require exactly 32 bytes`(count: Int) {
        #expect(throws: ValidationError.invalidAddress) {
            try Address(bytes: Array(repeating: UInt8(1), count: count))
        }
    }
}
