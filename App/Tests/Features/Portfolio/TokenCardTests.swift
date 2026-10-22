import Portfolio
import SwiftUI
import Testing
@testable import widgets

/// Checks that a token card places its figures beside the name when both fit, and under it otherwise.
@MainActor
struct TokenCardTests {
    /// Measures a card's height at a width.
    /// - Parameter width: The width offered to the card.
    /// - Returns: The height the card takes.
    /// - Throws: A failed expectation when the card doesn't render.
    private func height(atWidth width: CGFloat) throws -> CGFloat {
        let renderer = ImageRenderer(content: TokenCard(symbol: "MYST", name: "Mystery Token With A Long Name",
                                                        amount: Amount(units: 42, decimals: 0),
                                                        value: (total: 2_075, currency: "USD"),
                                                        change: Decimal(string: "0.0129"), imageURL: nil))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return CGFloat(try #require(renderer.cgImage).height) / renderer.scale
    }

    @Test func `A narrow card stacks the figures under the name`() throws {
        #expect(try height(atWidth: 220) > height(atWidth: 800))
    }

    @Test func `Each identity and figures view renders on its own`() throws {
        let secondary: ReadableSecondary = .readableSecondary(.black, on: .white)
        let identity = ImageRenderer(content: TokenCardIdentity(symbol: "SOL", name: "Solana", imageURL: nil,
                                                                secondary: secondary))
        let figures = ImageRenderer(content: TokenCardFigures(amount: nil, value: (total: 1, currency: "USD"),
                                                              change: nil, hasPrivateBalance: true,
                                                              secondary: secondary, alignment: .trailing))

        #expect(try #require(identity.cgImage).width > 0)
        #expect(try #require(figures.cgImage).width > 0)
    }
}
