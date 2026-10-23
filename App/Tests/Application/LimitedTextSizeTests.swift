import SwiftUI
import Testing
@testable import widgets

/// Checks that windows and sheets grow with the text size up to the largest standard size, and no further.
@MainActor
struct LimitedTextSizeTests {
    /// Measures the height of limited text at a text size.
    /// - Parameter textSize: The person's text size.
    /// - Returns: The height the text takes.
    /// - Throws: A failed expectation when the text doesn't render.
    private func height(at textSize: DynamicTypeSize) throws -> CGFloat {
        let renderer = ImageRenderer(content: Text(verbatim: "SOL")
            .font(.body)
            .limitedTextSize()
            .environment(\.dynamicTypeSize, textSize))
        return CGFloat(try #require(renderer.cgImage).height) / renderer.scale
    }

    @Test func `Accessibility text sizes stop at the largest standard size`() throws {
        let accessibility = try height(at: .accessibility5)
        let largestStandard = try height(at: .xxxLarge)
        #expect(accessibility == largestStandard)
    }

    @Test func `Standard text sizes still grow`() throws {
        let small = try height(at: .small)
        let largestStandard = try height(at: .xxxLarge)
        #expect(small < largestStandard)
    }
}
