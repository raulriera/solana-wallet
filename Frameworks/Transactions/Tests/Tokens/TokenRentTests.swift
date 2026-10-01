import Foundation
import Testing
import Transactions

/// Checks ATA allocation sizes against Token-2022 0.19.0's independent SDK output.
struct TokenRentTests {
    /// Verifies every supported combination includes immutable ownership and its required extensions.
    ///
    /// - Parameters:
    ///   - mask: The fee, disabled-hook, and unpaused-mint extension combination.
    ///   - expectedSize: The SDK's `getTokenSize` result, including `ImmutableOwner`.
    @Test("new Token-2022 destinations include the exact required extension space", arguments: [
        (0, UInt64(170)), (1, 182), (2, 175), (3, 187),
        (4, 174), (5, 186), (6, 179), (7, 191),
    ])
    func destinationSizeIncludesExtensions(mask: Int, expectedSize: UInt64) throws {
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

        #expect(transfer.destinationAccountSize == expectedSize)
    }

    /// Verifies existing accounts request no allocation and legacy ATA creation uses 165 bytes.
    ///
    /// - Parameter fixture: Either token program with an existing or absent destination.
    @Test("only absent token destinations require an allocation", arguments: TokenFixtures.transfers)
    func onlyAbsentDestinationsRequireAllocation(_ fixture: TokenFixture) throws {
        let transfer = try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
            mint: fixture.mint(), source: fixture.source(),
            destination: fixture.createsDestination ? nil : fixture.target(), amount: 1)

        let expected: UInt64? = fixture.createsDestination ? (transfer.mint.program == .token ? 165 : 170) : nil
        #expect(transfer.destinationAccountSize == expected)
    }

    /// TLV bytes produced offline by the SDK's `getExtensionEncoder`; no SDK runs in tests.
    private static let extensions = [
        (mint: "AQBsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA6AMAAAAAAAAZAGQAAAAAAAAAMgAAAAAAAABkAA==",
         account: "AgAIAAAAAAAAAAAA"),
        (mint: "DgBAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
         account: "DwABAAA="),
        (mint: "GgAhAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==", account: "GwAAAA=="),
    ]
}
