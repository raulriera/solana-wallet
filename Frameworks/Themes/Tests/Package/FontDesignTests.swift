import Testing
import Themes

struct FontDesignTests {
    @Test(arguments: [("default", FontDesign.default), ("rounded", .rounded)])
    func `Reads each supported font design`(token: String, design: FontDesign) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(#""tokens":{"fontDesign":"\#(token)"}"#)
        #expect(try await fixture.resolved().fontDesign == design)
    }
}
