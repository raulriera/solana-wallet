import Foundation
import Testing
@testable import widgets

/// Checks that values kept as JSON come back unchanged, and that other bytes are refused.
struct JSONCodingTests {
    /// Saved settings, including a custom URL that holds a key, come back as they were saved.
    /// - Throws: An encoding or test prerequisite error.
    @Test
    func `Settings come back as they were saved`() throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token?api-key=fixture-key"))
        let settings = ProviderSettings(selection: .custom(custom), customRPCs: [custom])
        let coding: JSONCoding<ProviderSettings> = .json(ProviderSettings.self)

        #expect(coding.decode(try coding.encode(settings)) == settings)
    }

    /// Bytes that aren't JSON for the type decode to nothing instead of a default value.
    @Test
    func `Bytes that aren't settings decode to nothing`() {
        #expect(JSONCoding<ProviderSettings>().decode(Data("not settings".utf8)) == nil)
    }
}
