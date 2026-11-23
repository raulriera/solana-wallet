import Testing
import Themes

struct ResolutionTests {
    @Test(arguments: [
        "", #""tokens":{}"#, #""tokens":{"colors":{}}"#,
        #""tokens":{"colors":{"light":{"invented":{"system":"label"}}}}"#
    ])
    func `Omitted and unknown settings use defaults`(fields: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(fields)
        #expect(try await fixture.resolved() == Fixture.defaults)
    }

    @Test(arguments: ["light", "dark"])
    func `Overrides stay within their appearance`(appearance: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(##""tokens":{"colors":{"\##(appearance)":{"primary":{"srgb":"#12aB34"}}}}"##)
        let result = try await fixture.resolved()
        let actual = ["light": result.colors.light, "dark": result.colors.dark]
        let defaults = ["light": Fixture.defaults.colors.light, "dark": Fixture.defaults.colors.dark]
        for (key, palette) in actual {
            let baseline = try #require(defaults[key])
            let expected = key == appearance
                ? Palette { $0 == .primary ? .srgb(red: 18, green: 171, blue: 52) : baseline[$0] }
                : baseline
            #expect(palette == expected)
        }
    }

    @Test func `Unknown keys in a color are ignored`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(#""tokens":{"colors":{"light":{"primary":{"system":"label","note":"Brand"}}}}"#)
        #expect(try await fixture.resolved().colors.light[.primary] == .system(.label))
    }

    @Test(arguments: Themes.Color.System.allCases)
    func `System references remain symbolic`(color: Themes.Color.System) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(#""tokens":{"colors":{"light":{"primary":{"system":"\#(color.rawValue)"}}}}"#)
        let result = try await fixture.resolved()
        #expect(result.colors.light[.primary] == .system(color))
    }

    @Test func `Matching foreground and background are accepted`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(##""tokens":{"colors":{"light":{"background":{"srgb":"#000000"},"text":{"srgb":"#000000"}}}}"##)
        let result = try await fixture.resolved()
        #expect(result.colors.light[.background] == result.colors.light[.text])
    }
}
