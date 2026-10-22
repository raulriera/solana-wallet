import Portfolio
import SwiftUI
import Testing
@testable import widgets

/// Checks that a token row places its figures beside the name when both fit, and under it otherwise.
@MainActor
struct TokenRowTests {
    /// Measures a row's height at a width.
    /// - Parameter width: The width offered to the row.
    /// - Returns: The height the row takes.
    /// - Throws: A failed expectation when the row doesn't render.
    private func height(atWidth width: CGFloat) throws -> CGFloat {
        let renderer = ImageRenderer(content: TokenRow(symbol: "MYST", name: "Mystery Token With A Long Name",
                                                       amount: Amount(units: 42, decimals: 0),
                                                       value: (total: 2_075, currency: "USD"),
                                                       change: Decimal(string: "0.0129"), imageURL: nil))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return CGFloat(try #require(renderer.cgImage).height) / renderer.scale
    }

    @Test func `A narrow row stacks the figures under the name`() throws {
        #expect(try height(atWidth: 220) > height(atWidth: 800))
    }

    @Test func `Each identity and figures view renders on its own`() throws {
        let identity = ImageRenderer(content: TokenRowIdentity(symbol: "SOL", name: "Solana", imageURL: nil))
        let figures = ImageRenderer(content: TokenRowFigures(amount: nil, value: (total: 1, currency: "USD"),
                                                             change: nil, hasPrivateBalance: true,
                                                             alignment: .trailing))

        #expect(try #require(identity.cgImage).width > 0)
        #expect(try #require(figures.cgImage).width > 0)
    }
}
