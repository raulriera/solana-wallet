import Foundation
import Testing
import Transactions

/// Verifies strict Base58 validation at the public address boundary.
struct AddressTests {
    private static let malformedAddresses: [String] = [
        "9WzDXwBbmkg8ZTbNMqUxvQRАyrZzDsGYdLVL9zYtAWWM", // Cyrillic А, U+0410.
        String(repeating: "1", count: 31),
        String(repeating: "1", count: 33),
    ]

    /// Verifies malformed input cannot silently become another valid address.
    ///
    /// - Parameter value: A lookalike address or valid Base58 with the wrong Solana width.
    @Test(arguments: malformedAddresses)
    func `Addresses require strict Base58 and exactly 32 bytes`(_ value: String) {
        #expect(throws: ValidationError.invalidAddress) { try Address(value) }
    }

    /// Verifies a stored address keeps its exact text and decodes to the same address.
    @Test
    func `Addresses encode as their Base58 text and decode unchanged`() throws {
        let address = try Address("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        let data = try JSONEncoder().encode(address)
        #expect(String(decoding: data, as: UTF8.self) == #""9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM""#)
        #expect(try JSONDecoder().decode(Address.self, from: data) == address)
    }

    /// Verifies stored text gets the same validation as text passed to the initializer.
    ///
    /// - Parameter value: A lookalike address or valid Base58 with the wrong Solana width.
    @Test(arguments: malformedAddresses)
    func `Decoding rejects text that isn't a valid address`(_ value: String) throws {
        let data = try JSONEncoder().encode(value)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Address.self, from: data) }
    }
}
