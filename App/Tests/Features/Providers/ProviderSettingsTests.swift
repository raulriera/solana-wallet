import Foundation
import Testing
@testable import widgets

/// Checks the saved settings' defaults and the rules that the provider selection doesn't exercise.
struct ProviderSettingsTests {
    /// Without a saved choice, Helius stays in use and no custom RPCs exist, as before this setting.
    @Test
    func `New settings select Helius without custom RPCs`() {
        let settings = ProviderSettings()

        #expect(settings.selection == .helius)
        #expect(settings.customRPCs.isEmpty)
    }

    /// A custom RPC shows only its host, so a key in its URL never appears on screen.
    /// - Throws: A test prerequisite error.
    @Test
    func `A custom RPC shows only its host`() throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token?api-key=fixture-key"))

        #expect(String(localized: ProviderSettings.Provider.custom(custom).name) == "rpc.example.com")
    }

    /// Adding an RPC that's already listed only chooses it, so the list never repeats an RPC.
    /// - Throws: A test prerequisite error.
    @Test
    func `Adding a listed RPC only chooses it`() throws {
        let listed = try #require(URL(string: "https://one.example.com"))
        var settings = ProviderSettings(customRPCs: [listed])

        settings.add(listed)

        #expect(settings == ProviderSettings(selection: .custom(listed), customRPCs: [listed]))
    }

    /// An RPC that isn't listed can't be chosen.
    /// - Throws: A test prerequisite error.
    @Test
    func `An unlisted custom RPC can't be chosen`() throws {
        let unlisted = try #require(URL(string: "https://one.example.com"))
        var settings = ProviderSettings()

        settings.select(.custom(unlisted))

        #expect(settings == ProviderSettings())
    }
}
