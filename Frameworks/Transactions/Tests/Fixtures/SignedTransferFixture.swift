import Foundation
import Testing

/// A public BIP-39 account transferring one SOL, signed and encoded with Solana Kit 8.0.0.
///
/// The blockhash is an offline placeholder. This fixture must never secure real funds.
enum SignedTransferFixture {
    static let sender = "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk"
    static let message = "gQEAAQ8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAED8DYnYkanW53jNJ7UKxXiMvZRj8IPX81PHWToH5vSWPd+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAiBMAAAAAAAAgTgAAAAABAAICDAAAAQIAAAAAypo7AAAAAA=="
    static let signature = "P4bk0tvnKMO5RvBarhhyz0Ijx5iYiacOX01Z3pXgEKrDdXGPQf9WwRF7SL+J+AHjE5bPgeZL/WruwhE4R1PyDQ=="
    static let otherSignature = "zSx0DH2gwF8OK3DPnYsWW9dtn9/c8wv6xunomytBPAofV5+y67R0vU7lVaihGalx9a+nsCeqWpvkWOglZQhVAA=="
    /// A deliberately unsafe nonce: R is the identity and S = SHA512(R || A || message) × a mod L.
    /// Generated independently with Node SHA-512 and the public fixture's derived scalar.
    static let identityNonceSignature = "AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC8Yv2qwkvB+9WGmHYdXIj/Qb3Zj59r8/IDf7O3c7OeCA=="
    static let transaction = "gQEAAQ8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAED8DYnYkanW53jNJ7UKxXiMvZRj8IPX81PHWToH5vSWPd+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAiBMAAAAAAAAgTgAAAAABAAICDAAAAQIAAAAAypo7AAAAAD+G5NLb5yjDuUbwWq4Ycs9CI8eYmImnDl9NWd6V4BCqw3Vxj0H/VsERe0i/ifgB4xOWz4HmS/1q7sIROEdT8g0="

    /// Decodes a fixture without silently substituting empty data.
    ///
    /// - Parameter value: Base64 produced by the independent fixture generator.
    /// - Returns: The original fixture bytes.
    /// - Throws: A test failure if the fixture is malformed.
    static func bytes(_ value: String) throws -> Data {
        try #require(Data(base64Encoded: value))
    }
}
