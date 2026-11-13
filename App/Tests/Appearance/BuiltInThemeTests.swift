import Testing
import Themes
@testable import widgets

struct BuiltInThemeTests {
    @Test(arguments: [BundledTheme.original, .solana])
    func `A built-in theme reads as a valid pack with its identity and name`(theme: BundledTheme?) async throws {
        let theme = try #require(theme)
        let pack = try await PackService().read(from: theme.url)
        #expect(pack.id == theme.entry.id)
        #expect(pack.name == theme.entry.name)
    }
}
