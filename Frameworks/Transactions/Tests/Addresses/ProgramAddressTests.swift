import Foundation
import Testing
@testable import Transactions

/// Checks the public-data arithmetic used to derive associated token accounts.
struct ProgramAddressTests {
    /// Verifies curve membership against independent SDK decompression over fixed public hashes.
    @Test
    func `Curve membership matches independent public point encodings`() throws {
        for sample in TokenFixtures.curveSamples {
            let bytes = Array(try #require(Data(base64Encoded: sample.encoded)))
            #expect(EdwardsPoint.isOnCurve(bytes) == sample.onCurve)
        }
        // Dalek accepts unreduced y aliases and either sign for an x=0 point.
        for first: UInt8 in [0xed, 0xee] {
            let bytes = [first] + Array(repeating: UInt8(0xff), count: 30) + [0x7f]
            #expect(EdwardsPoint.isOnCurve(bytes))
        }
    }

    /// Verifies both programs, off-curve owners, and bump searches extending down to 250.
    @Test
    func `Associated accounts match SDK derivation for both token programs`() throws {
        for sample in TokenFixtures.associatedAccounts {
            let fixture = TokenFixtures.transfers[sample.program == TokenProgram.token.rawValue ? 0 : 2]
            let mint = try fixture.mint()
            #expect(try mint.associatedAccount(for: Address(sample.owner)).value == sample.expected)
        }
    }
}
