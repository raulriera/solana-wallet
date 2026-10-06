import Foundation
import Testing
@testable import widgets

/// Checks logo decoding and region sampling with generated logos.
struct ArtworkSamplerTests {
    /// The logo's own color wins over its white border and background.
    @Test
    func `A colored logo inside a white border keeps its color`() throws {
        let png = try ArtworkFixture.png(center: (0.2, 0.5, 0.8))
        let color = try #require(ArtworkSampler.color(from: png))
        #expect(abs(color.red - 0.2) < 0.02)
        #expect(abs(color.green - 0.5) < 0.02)
        #expect(abs(color.blue - 0.8) < 0.02)
    }

    /// A gray logo gives no color, so its card keeps the neutral surface.
    @Test
    func `A logo with only neutral pixels has no color`() throws {
        let png = try ArtworkFixture.png(border: 0.9, center: (0.4, 0.4, 0.4))
        #expect(ArtworkSampler.color(from: png) == nil)
    }

    /// Data that the system can't decode gives no color instead of an invented one.
    @Test
    func `Data that is not an image has no color`() {
        #expect(ArtworkSampler.color(from: Data("not-image-data".utf8)) == nil)
    }
}
