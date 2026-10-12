import Foundation
import Testing
@testable import widgets

/// Checks how provider choices and custom RPCs change the saved settings.
struct ProviderSettingsTests {
    /// Without a saved choice, Helius stays in use and no custom RPCs exist, as before this setting.
    @Test
    func `New settings select Helius without custom RPCs`() {
        let settings = ProviderSettings()

        #expect(settings.selection == .helius)
        #expect(settings.customRPCs.isEmpty)
    }

    /// Choosing another provider changes the selection and keeps the custom RPCs.
    /// - Throws: A test prerequisite error.
    @Test
    func `A new choice changes the selection and keeps the custom RPCs`() throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        var settings = ProviderSettings(customRPCs: [custom])

        let changed = settings.select(.custom(custom))

        #expect(changed)
        #expect(settings == ProviderSettings(selection: .custom(custom), customRPCs: [custom]))
    }

    /// A custom RPC shows only its host, so a key in its URL never appears on screen.
    /// - Throws: A test prerequisite error.
    @Test
    func `A custom RPC shows only its host`() throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token?api-key=fixture-key"))

        #expect(String(localized: ProviderSettings.Provider.custom(custom).name) == "rpc.example.com")
    }

    /// Choosing the provider in use changes nothing.
    @Test
    func `Choosing the provider in use changes nothing`() {
        var settings = ProviderSettings()

        let changed = settings.select(.helius)

        #expect(changed == false)
        #expect(settings == ProviderSettings())
    }

    /// Adding a custom RPC lists it after the others and chooses it.
    /// - Throws: A test prerequisite error.
    @Test
    func `Adding a custom RPC lists it and chooses it`() throws {
        let listed = try #require(URL(string: "https://one.example.com"))
        let added = try #require(URL(string: "https://two.example.com"))
        var settings = ProviderSettings(customRPCs: [listed])

        let changed = settings.add(added)

        #expect(changed)
        #expect(settings == ProviderSettings(selection: .custom(added), customRPCs: [listed, added]))
    }

    /// Adding an RPC that's already listed only chooses it, so the list never repeats an RPC.
    /// - Throws: A test prerequisite error.
    @Test
    func `Adding a listed RPC only chooses it`() throws {
        let listed = try #require(URL(string: "https://one.example.com"))
        var settings = ProviderSettings(customRPCs: [listed])

        let changed = settings.add(listed)

        #expect(changed)
        #expect(settings == ProviderSettings(selection: .custom(listed), customRPCs: [listed]))
    }

    /// An RPC that isn't listed can't be chosen.
    /// - Throws: A test prerequisite error.
    @Test
    func `An unlisted custom RPC can't be chosen`() throws {
        let unlisted = try #require(URL(string: "https://one.example.com"))
        var settings = ProviderSettings()

        let changed = settings.select(.custom(unlisted))

        #expect(changed == false)
        #expect(settings == ProviderSettings())
    }

    /// Adding the custom RPC in use changes nothing.
    /// - Throws: A test prerequisite error.
    @Test
    func `Adding the custom RPC in use changes nothing`() throws {
        let listed = try #require(URL(string: "https://one.example.com"))
        var settings = ProviderSettings(selection: .custom(listed), customRPCs: [listed])

        let changed = settings.add(listed)

        #expect(changed == false)
        #expect(settings == ProviderSettings(selection: .custom(listed), customRPCs: [listed]))
    }

    /// Removing the custom RPC in use chooses Solana.
    /// - Throws: A test prerequisite error.
    @Test
    func `Removing the custom RPC in use chooses Solana`() throws {
        let removed = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        var settings = ProviderSettings(selection: .custom(removed), customRPCs: [removed, kept])

        let selectionChanged = settings.remove(removed)

        #expect(selectionChanged)
        #expect(settings == ProviderSettings(selection: .solana, customRPCs: [kept]))
    }

    /// Removing another custom RPC keeps the provider in use.
    /// - Throws: A test prerequisite error.
    @Test
    func `Removing another custom RPC keeps the provider in use`() throws {
        let removed = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        var settings = ProviderSettings(selection: .custom(kept), customRPCs: [removed, kept])

        let selectionChanged = settings.remove(removed)

        #expect(selectionChanged == false)
        #expect(settings == ProviderSettings(selection: .custom(kept), customRPCs: [kept]))
    }
}
