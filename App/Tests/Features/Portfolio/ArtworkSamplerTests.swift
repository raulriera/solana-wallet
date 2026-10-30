import Foundation
import Testing
@testable import widgets

struct ArtworkSamplerTests {
    @Test
    func `A colored logo inside a white border keeps its color`() throws {
        let png = try ArtworkFixture.png(center: (0.2, 0.5, 0.8))
        let color = try #require(ArtworkSampler.color(from: png))
        #expect(abs(color.red - 0.2) < 0.02)
        #expect(abs(color.green - 0.5) < 0.02)
        #expect(abs(color.blue - 0.8) < 0.02)
    }

    @Test
    func `A gradient logo with thin bars keeps its largest color`() throws {
        let url = try #require(Bundle.main.url(forResource: "sol", withExtension: "png"))
        let color = try #require(ArtworkSampler.color(from: try Data(contentsOf: url)))
        #expect(color.blue > color.red && color.red > color.green)
    }

    @Test
    func `A logo with only neutral pixels has no color`() throws {
        let png = try ArtworkFixture.png(border: 0.9, center: (0.4, 0.4, 0.4))
        #expect(ArtworkSampler.color(from: png) == nil)
    }

    @Test
    func `Data that is not an image has no color`() {
        #expect(ArtworkSampler.color(from: Data("not-image-data".utf8)) == nil)
    }
}
