import Foundation
import Storage
import Testing
@testable import widgets

/// Checks the saved settings' defaults and the rules that the provider selection doesn't exercise.
struct ProviderSettingsTests {
    /// Without a saved choice, Solana's public RPC is in use, so a wallet loads without a key, and no custom RPCs exist.
    @Test
    func `New settings select Solana without custom RPCs`() {
        let settings = ProviderSettings()

        #expect(settings.selection == .solana)
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

    /// Saved settings, including a custom URL that holds a key, come back as they were saved.
    /// - Throws: An encoding or test prerequisite error.
    @Test
    func `Settings come back as they were saved`() throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token?api-key=fixture-key"))
        let settings = ProviderSettings(selection: .custom(custom), customRPCs: [custom])
        let coding: JSONCoding<ProviderSettings> = .json(ProviderSettings.self)

        #expect(coding.decode(try coding.encode(settings)) == settings)
    }
}
