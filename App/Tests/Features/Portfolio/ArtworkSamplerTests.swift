import Foundation
import Testing
@testable import widgets

/// Checks logo decoding and region sampling with generated and bundled logos.
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

    /// A gradient of thin bars on a dark background still gives its largest color when its edges blend into the
    /// background.
    ///
    /// The SOL logo runs from purple to green through blue; its purple region is the largest.
    /// - Throws: An error if the bundled SOL logo can't be found, read, or sampled.
    @Test
    func `A gradient logo with thin bars keeps its largest color`() throws {
        let url = try #require(Bundle.main.url(forResource: "sol", withExtension: "png"))
        let color = try #require(ArtworkSampler.color(from: try Data(contentsOf: url)))
        #expect(color.blue > color.red && color.red > color.green)
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
