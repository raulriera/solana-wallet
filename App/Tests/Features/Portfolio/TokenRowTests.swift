import Portfolio
import SwiftUI
import Testing
@testable import widgets

/// Checks that a token row keeps its name and figures on one line, truncating the name.
@MainActor
struct TokenRowTests {
    /// A mint address, which a token without metadata shows as its symbol and name.
    private static let mint = "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"

    /// Measures a row's height at a width.
    /// - Parameters:
    ///   - width: The width offered to the row.
    ///   - symbol: The token's symbol.
    ///   - name: The token's name.
    /// - Returns: The height the row takes.
    /// - Throws: A failed expectation when the row doesn't render.
    private func height(atWidth width: CGFloat, symbol: String = "MYST", name: String = "Mystery Token")
        throws -> CGFloat {
        let renderer = ImageRenderer(content: TokenRow(symbol: symbol, name: name,
                                                       amount: Amount(units: 42, decimals: 0),
                                                       value: (total: 2_075, currency: "USD"),
                                                       change: Decimal(string: "0.0129"), imageURL: nil))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return CGFloat(try #require(renderer.cgImage).height) / renderer.scale
    }

    @Test func `A narrow row keeps the figures beside the name`() throws {
        let narrow = try height(atWidth: 220)
        let wide = try height(atWidth: 800)
        #expect(narrow == wide)
    }

    @Test func `A long symbol and name truncate to one line each`() throws {
        let long = try height(atWidth: 375, symbol: Self.mint, name: Self.mint)
        let short = try height(atWidth: 375)
        #expect(long == short)
    }

    @Test func `Each identity and figures view renders on its own`() throws {
        let identity = ImageRenderer(content: TokenRowIdentity(symbol: "SOL", name: "Solana", imageURL: nil))
        let figures = ImageRenderer(content: TokenRowFigures(amount: nil, value: (total: 1, currency: "USD"),
                                                             change: nil, hasPrivateBalance: true))

        #expect(try #require(identity.cgImage).width > 0)
        #expect(try #require(figures.cgImage).width > 0)
    }
}
