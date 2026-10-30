import Foundation
import Testing
@testable import Transactions

struct ProgramAddressTests {
    private static let shieldedPool = "sppU489D7A4U1exNo1oeMGZtLEofq3a6o2fR7UeoWB6"

    @Test(arguments: [
        ([Array("cpi_authority".utf8)], "4547dcb9d88f9e90c2c0233ac024ea5781fef073882259cf0df16350bd1c54eb", 255),
        ([Array("sol_interface".utf8), [0]], "196756c885b9985ace5f78749c1d5fd1738ca0fae278321e27235883a4fefc92", 252),
    ] as [([[UInt8]], String, UInt8)])
    func `Derived addresses and bumps match zolana's pinned constants`(seeds: [[UInt8]], hex: String, bump: UInt8) throws {
        let derived = try ProgramAddress.find(seeds: seeds, program: Address(Self.shieldedPool))

        #expect(derived.address.bytes == (try fixtureBytes(hex)))
        #expect(derived.bump == bump)
    }

    @Test
    func `Fifteen seeds of 32 bytes derive an address`() throws {
        let seeds = (0..<15).map { [UInt8](repeating: UInt8($0), count: 32) }

        #expect(try ProgramAddress.find(seeds: seeds, program: Address(Self.shieldedPool)).address.isOnCurve == false)
    }

    @Test(arguments: [
        (0..<16).map { _ in [UInt8(1)] },
        [[UInt8](repeating: 1, count: 33)],
    ])
    func `Seeds beyond Solana's limits are rejected`(seeds: [[UInt8]]) {
        #expect(throws: ValidationError.invalidSeeds) {
            try ProgramAddress.find(seeds: seeds, program: Address(Self.shieldedPool))
        }
    }

    @Test(arguments: TokenFixtures.curveSamples)
    func `Curve membership matches independent public point encodings`(encoded: String, onCurve: Bool) throws {
        let bytes = Array(try #require(Data(base64Encoded: encoded)))
        #expect(EdwardsPoint.isOnCurve(bytes) == onCurve)
    }

    @Test(arguments: [UInt8(0xed), 0xee])
    func `Curve membership accepts unreduced y aliases`(first: UInt8) {
        let bytes = [first] + Array(repeating: UInt8(0xff), count: 30) + [0x7f]
        #expect(EdwardsPoint.isOnCurve(bytes))
    }

    @Test(arguments: TokenFixtures.associatedAccounts)
    func `Associated accounts match SDK derivation for both token programs`(owner: String, program: String, expected: String) throws {
        let fixture = TokenFixtures.transfers[program == TokenProgram.token.rawValue ? 0 : 2]
        let mint = try fixture.mint()
        #expect(try mint.program.associatedAccount(owner: Address(owner), mint: mint.address).value == expected)
    }
}
