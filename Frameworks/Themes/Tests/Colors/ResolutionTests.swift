import Testing
import Themes

struct ResolutionTests {
    /// Omitted settings retain complete app-provided values in every appearance.
    @Test(arguments: ["", #""tokens":{}"#, #""tokens":{"colors":{}}"#])
    func `Omitted settings use defaults`(fields: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(fields)
        let service: any PackServicing = PackService()
        let pack = try await service.read(from: fixture.source)
        #expect(service.resolve(pack, defaults: Fixture.defaults) == Fixture.defaults)
    }

    /// An override changes only its appearance and role without applying a contrast gate.
    @Test(arguments: ["light", "dark", "lightIncreasedContrast", "darkIncreasedContrast"])
    func `Overrides stay within their appearance`(appearance: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(##""tokens":{"colors":{"\##(appearance)":{"accent":{"srgb":"#12aB34"}}}}"##)
        let service = PackService()
        let result = service.resolve(try await service.read(from: fixture.source), defaults: Fixture.defaults)
        let actual = ["light": result.light, "dark": result.dark,
                      "lightIncreasedContrast": result.lightIncreasedContrast,
                      "darkIncreasedContrast": result.darkIncreasedContrast]
        let defaults = ["light": Fixture.defaults.light, "dark": Fixture.defaults.dark,
                        "lightIncreasedContrast": Fixture.defaults.lightIncreasedContrast,
                        "darkIncreasedContrast": Fixture.defaults.darkIncreasedContrast]
        for (key, palette) in actual {
            let baseline = try #require(defaults[key])
            let expected = key == appearance
                ? Palette(background: baseline.background, surface: baseline.surface, primaryText: baseline.primaryText,
                          secondaryText: baseline.secondaryText, separator: baseline.separator,
                          accent: .srgb(red: 18, green: 171, blue: 52), onAccent: baseline.onAccent)
                : baseline
            #expect(palette == expected)
        }
    }

    /// Symbolic color names are accepted without flattening them into one appearance.
    @Test(arguments: Themes.Color.System.allCases)
    func `System references remain symbolic`(color: Themes.Color.System) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(#""tokens":{"colors":{"light":{"accent":{"system":"\#(color.rawValue)"}}}}"#)
        let service = PackService()
        let result = service.resolve(try await service.read(from: fixture.source), defaults: Fixture.defaults)
        #expect(result.light.accent == .system(color))
    }

    /// Readable structure, rather than custom-theme contrast, determines acceptance.
    @Test func `Matching foreground and background are accepted`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(##""tokens":{"colors":{"light":{"background":{"srgb":"#000000"},"primaryText":{"srgb":"#000000"}}}}"##)
        let service = PackService()
        let result = service.resolve(try await service.read(from: fixture.source), defaults: Fixture.defaults)
        #expect(result.light.background == result.light.primaryText)
    }
}
