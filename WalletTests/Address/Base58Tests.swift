import Testing
@testable import Wallet

/// Tests the leading-zero convention used by Solana addresses.
struct Base58Tests {
    /// Verifies leading zero bytes and carry propagation in Base58 encoding.
    ///
    /// - Parameters:
    ///   - bytes: The binary value to encode.
    ///   - expected: Its Base58 representation.
    @Test("Base58 preserves leading zero bytes", arguments: [
        ([UInt8](repeating: 0, count: 32), String(repeating: "1", count: 32)),
        ([UInt8](arrayLiteral: 0, 0, 1), "112"),
        ([UInt8](arrayLiteral: 0, 255), "15Q"),
        ([UInt8](arrayLiteral: 255, 255), "LUv"),
    ])
    func base58PreservesLeadingZeroBytes(bytes: [UInt8], expected: String) {
        #expect(Base58.encode(bytes) == expected)
    }
}
