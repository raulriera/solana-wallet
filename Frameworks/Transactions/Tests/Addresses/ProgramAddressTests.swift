import Foundation
import Testing
@testable import Transactions

/// Checks program-derived address searches and the public-data arithmetic behind them.
///
/// The shielded-pool addresses are the constants that zolana v0.4.0-alpha (Apache-2.0) pins in
/// `program-libs/interface/src/lib.rs`: the shielded-pool program's CPI authority and native-SOL
/// custody PDAs, copied unchanged as hexadecimal with their bumps.
struct ProgramAddressTests {
    /// The shielded-pool program that owns both pinned addresses.
    private static let shieldedPool = "sppU489D7A4U1exNo1oeMGZtLEofq3a6o2fR7UeoWB6"

    /// Verifies derived addresses and bumps against zolana's pinned shielded-pool constants.
    ///
    /// The CPI authority takes the first bump, 255; the SOL interface searches down to 252.
    ///
    /// - Parameters:
    ///   - seeds: The seeds, without the bump.
    ///   - hex: The pinned address bytes.
    ///   - bump: The pinned canonical bump.
    @Test(arguments: [
        ([Array("cpi_authority".utf8)], "4547dcb9d88f9e90c2c0233ac024ea5781fef073882259cf0df16350bd1c54eb", 255),
        ([Array("sol_interface".utf8), [0]], "196756c885b9985ace5f78749c1d5fd1738ca0fae278321e27235883a4fefc92", 252),
    ] as [([[UInt8]], String, UInt8)])
    func `Derived addresses and bumps match zolana's pinned constants`(seeds: [[UInt8]], hex: String, bump: UInt8) throws {
        let derived = try ProgramAddress.find(seeds: seeds, program: Address(Self.shieldedPool))

        #expect(derived.address.bytes == (try fixtureBytes(hex)))
        #expect(derived.bump == bump)
    }

    /// Verifies that the largest seed list Solana accepts, 15 seeds of 32 bytes, derives an address.
    @Test
    func `Fifteen seeds of 32 bytes derive an address`() throws {
        let seeds = (0..<15).map { [UInt8](repeating: UInt8($0), count: 32) }

        #expect(try ProgramAddress.find(seeds: seeds, program: Address(Self.shieldedPool)).address.isOnCurve == false)
    }

    /// Verifies that seed lists beyond Solana's limits are rejected before any hashing.
    ///
    /// - Parameter seeds: Sixteen seeds, which leave no room for the bump, or one 33-byte seed.
    @Test(arguments: [
        (0..<16).map { _ in [UInt8(1)] },
        [[UInt8](repeating: 1, count: 33)],
    ])
    func `Seeds beyond Solana's limits are rejected`(seeds: [[UInt8]]) {
        #expect(throws: ValidationError.invalidSeeds) {
            try ProgramAddress.find(seeds: seeds, program: Address(Self.shieldedPool))
        }
    }

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

    /// Verifies both programs, off-curve owners, and bump searches extending down to 250.
    /// - Parameters:
    ///   - owner: The public wallet address used for derivation.
    ///   - program: The token program owning the fixture mint.
    ///   - expected: The associated account derived by the independent SDK.
    @Test(arguments: TokenFixtures.associatedAccounts)
    func `Associated accounts match SDK derivation for both token programs`(owner: String, program: String, expected: String) throws {
        let fixture = TokenFixtures.transfers[program == TokenProgram.token.rawValue ? 0 : 2]
        let mint = try fixture.mint()
        #expect(try mint.program.associatedAccount(owner: Address(owner), mint: mint.address).value == expected)
    }
}
