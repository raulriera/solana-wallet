import Foundation
import Testing
@testable import Transactions

/// Checks the public-data arithmetic used to derive associated token accounts.
struct ProgramAddressTests {
    /// Verifies curve membership against independent SDK decompression over fixed public hashes.
    /// - Parameters:
    ///   - encoded: The public point's Base64 encoding.
    ///   - onCurve: The independent SDK's curve-membership result.
    @Test(arguments: TokenFixtures.curveSamples)
    func `Curve membership matches independent public point encodings`(encoded: String, onCurve: Bool) throws {
        let bytes = Array(try #require(Data(base64Encoded: encoded)))
        #expect(EdwardsPoint.isOnCurve(bytes) == onCurve)
    }

    /// Verifies Dalek-compatible acceptance of unreduced y aliases for an x=0 point.
    /// - Parameter first: The low byte distinguishing the accepted aliases.
    @Test(arguments: [UInt8(0xed), 0xee])
    func `Curve membership accepts unreduced y aliases`(first: UInt8) {
        let bytes = [first] + Array(repeating: UInt8(0xff), count: 30) + [0x7f]
        #expect(EdwardsPoint.isOnCurve(bytes))
    }

    /// Verifies both programs, off-curve owners, and bump searches extending down to 250,
    /// from a decoded mint and from a mint address alone.
    /// - Parameters:
    ///   - owner: The public wallet address used for derivation.
    ///   - program: The token program owning the fixture mint.
    ///   - expected: The associated account derived by the independent SDK.
    @Test(arguments: TokenFixtures.associatedAccounts)
    func `Associated accounts match SDK derivation for both token programs`(owner: String, program: String, expected: String) throws {
        let fixture = TokenFixtures.transfers[program == TokenProgram.token.rawValue ? 0 : 2]
        let mint = try fixture.mint()
        #expect(try mint.associatedAccount(for: Address(owner)).value == expected)
        #expect(try mint.program.associatedAccount(owner: Address(owner), mint: mint.address).value == expected)
    }
}
