import Testing
import Themes

struct ResolutionTests {
    @Test(arguments: ["", #""tokens":{}"#, #""tokens":{"colors":{}}"#])
    func `Omitted settings use defaults`(fields: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(fields)
        let service: any PackServicing = PackService()
        let pack = try await service.read(from: fixture.source)
        #expect(service.resolve(pack, defaults: Fixture.defaults) == Fixture.defaults)
    }

    @Test(arguments: ["light", "dark", "lightIncreasedContrast", "darkIncreasedContrast"])
    func `Overrides stay within their appearance`(appearance: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(##""tokens":{"colors":{"\##(appearance)":{"primary":{"srgb":"#12aB34"}}}}"##)
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
                ? Palette(background: baseline.background, surface: baseline.surface, text: baseline.text,
                          secondaryText: baseline.secondaryText, separator: baseline.separator,
                          primary: .srgb(red: 18, green: 171, blue: 52), onPrimary: baseline.onPrimary,
                          secondary: baseline.secondary, onSecondary: baseline.onSecondary,
                          destructive: baseline.destructive, onDestructive: baseline.onDestructive)
                : baseline
            #expect(palette == expected)
        }
    }

    @Test(arguments: Themes.Color.System.allCases)
    func `System references remain symbolic`(color: Themes.Color.System) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(#""tokens":{"colors":{"light":{"primary":{"system":"\#(color.rawValue)"}}}}"#)
        let service = PackService()
        let result = service.resolve(try await service.read(from: fixture.source), defaults: Fixture.defaults)
        #expect(result.light.primary == .system(color))
    }

    @Test func `Matching foreground and background are accepted`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest(##""tokens":{"colors":{"light":{"background":{"srgb":"#000000"},"text":{"srgb":"#000000"}}}}"##)
        let service = PackService()
        let result = service.resolve(try await service.read(from: fixture.source), defaults: Fixture.defaults)
        #expect(result.light.background == result.light.text)
    }
}
