import Foundation
import Testing
import Transactions

struct TokenRentTests {
    @Test(arguments: [
        (0, UInt64(170)), (1, 182), (2, 175), (3, 187),
        (4, 174), (5, 186), (6, 179), (7, 191),
    ])
    func `New Token-2022 destinations include the exact required extension space`(mask: Int, expectedSize: UInt64) throws {
        let fixture = TokenFixtures.transfers[2]
        var mint = try #require(Data(base64Encoded: fixture.mintData))
        mint.append(Data(repeating: 0, count: 165 - mint.count))
        mint.append(1)
        var source = try #require(Data(base64Encoded: fixture.sourceData))
        source.append(2)
        for (index, entry) in Self.extensions.enumerated() where mask & (1 << index) != 0 {
            mint.append(try #require(Data(base64Encoded: entry.mint)))
            source.append(try #require(Data(base64Encoded: entry.account)))
        }
        let transfer = try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
            mint: fixture.mint(mint.base64EncodedString()), source: fixture.source(source),
            destination: nil, amount: 1, epoch: 100)

        #expect(try transfer.mint.associatedAccountSize == expectedSize)
    }

    @Test(arguments: TokenFixtures.transfers)
    func `Only absent token destinations are created at their program's account size`(_ fixture: TokenFixture) throws {
        let transfer = try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
            mint: fixture.mint(), source: fixture.source(),
            destination: fixture.createsDestination ? nil : fixture.target(), amount: 1)

        #expect(transfer.createsDestination == fixture.createsDestination)
        #expect(try transfer.mint.associatedAccountSize == (transfer.mint.program == .token ? 165 : 170))
    }

    private static let extensions = [
        (mint: "AQBsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA6AMAAAAAAAAZAGQAAAAAAAAAMgAAAAAAAABkAA==",
         account: "AgAIAAAAAAAAAAAA"),
        (mint: "DgBAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
         account: "DwABAAA="),
        (mint: "GgAhAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==", account: "GwAAAA=="),
    ]
}
