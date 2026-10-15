import Encoding
import Testing
@testable import Transactions

/// Verifies addresses that the framework builds from derived or decoded bytes.
struct AddressBytesTests {
    /// Verifies that an address built from bytes matches the same address parsed from its text.
    /// - Throws: An error if the fixture address is invalid.
    @Test
    func `Addresses from bytes match the address parsed from their text`() throws {
        let text = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
        let bytes = try #require(Base58.decode(text, byteCount: 32))

        let address = try Address(bytes: bytes)

        #expect(address == (try Address(text)))
        #expect(address.value == text)
    }

    /// Verifies that only exactly 32 bytes make an address.
    ///
    /// - Parameter count: A byte count other than 32.
    @Test(arguments: [0, 31, 33])
    func `Addresses from bytes require exactly 32 bytes`(count: Int) {
        #expect(throws: ValidationError.invalidAddress) {
            try Address(bytes: Array(repeating: UInt8(1), count: count))
        }
    }
}
