import Foundation
import Testing

/// A Kit 8.0.0 V1 envelope with two signers and two opaque instructions.
///
/// The second signature is deliberately unverified (64 bytes of 0x55); the first
/// slot is empty. Instruction payloads have no asserted program meaning.
enum DecodingFixture {
    static let program = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"
    static let wire = "gQIBAR8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIEMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2B+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8vA2J2JGp1ud4zSe1CsV4jL2UY/CD1/NTx1k6B+b0lj3BUpTWpkpIQZNJOhxYNo4fHw1td28kruB5B+oQEEFRI3//////////yBOAAAAAAEAAIAAAAMEAwADAQIAAAECAQECAwIEBQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV"
    static let message = "gQIBAR8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIEMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2B+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8vA2J2JGp1ud4zSe1CsV4jL2UY/CD1/NTx1k6B+b0lj3BUpTWpkpIQZNJOhxYNo4fHw1td28kruB5B+oQEEFRI3//////////yBOAAAAAAEAAIAAAAMEAwADAQIAAAECAQECAwIEBQ=="

    // Offsets in the independent fixture: 42-byte header, four accounts, five config words.
    static let requestsStart = 170
    static let headersStart = 190
    static let payloadsStart = 198

    /// Decodes the independent SDK envelope for inspection or deliberate corruption.
    ///
    /// - Returns: The complete fixture including its two signature slots.
    /// - Throws: A test failure if the stored Base64 is invalid.
    static func transaction() throws -> Data {
        try #require(Data(base64Encoded: wire))
    }
}
