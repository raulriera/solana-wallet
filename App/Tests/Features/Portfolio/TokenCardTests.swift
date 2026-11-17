import SwiftUI
import Testing
import Transactions
@testable import widgets

@MainActor
struct TokenCardTests {
    private static let mint = "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"

    private func height(atWidth width: CGFloat, symbol: String = "MYST", name: String = "Mystery Token")
        throws -> CGFloat {
        let renderer = ImageRenderer(content: TokenCard(symbol: symbol, name: name,
                                                        balance: TokenAmount(amount: 42, decimals: 0),
                                                        value: (total: 2_075, currency: "USD"),
                                                        change: Decimal(string: "0.0129"), imageURL: nil))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return CGFloat(try #require(renderer.cgImage).height) / renderer.scale
    }

    @Test func `A narrow card keeps the figures beside the name`() throws {
        let narrow = try height(atWidth: 220)
        let wide = try height(atWidth: 800)
        #expect(narrow == wide)
    }

    @Test func `A long symbol and name truncate to one line each`() throws {
        let long = try height(atWidth: 375, symbol: Self.mint, name: Self.mint)
        let short = try height(atWidth: 375)
        #expect(long == short)
    }
}
