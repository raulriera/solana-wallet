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
}
