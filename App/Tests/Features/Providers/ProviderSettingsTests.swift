import Foundation
import Storage
import Testing
@testable import widgets

struct ProviderSettingsTests {
    @Test
    func `New settings select Solana without custom RPCs`() {
        let settings = ProviderSettings()

        #expect(settings.selection == .solana)
        #expect(settings.customRPCs.isEmpty)
    }

    @Test
    func `A custom RPC shows only its host`() throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token?api-key=fixture-key"))

        #expect(String(localized: ProviderSettings.Provider.custom(custom).name) == "rpc.example.com")
    }

    @Test
    func `Adding a listed RPC only chooses it`() throws {
        let listed = try #require(URL(string: "https://one.example.com"))
        var settings = ProviderSettings(customRPCs: [listed])

        settings.add(listed)

        #expect(settings == ProviderSettings(selection: .custom(listed), customRPCs: [listed]))
    }

    @Test
    func `An unlisted custom RPC can't be chosen`() throws {
        let unlisted = try #require(URL(string: "https://one.example.com"))
        var settings = ProviderSettings()

        settings.select(.custom(unlisted))

        #expect(settings == ProviderSettings())
    }

    @Test
    func `Settings come back as they were saved`() throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token?api-key=fixture-key"))
        let settings = ProviderSettings(selection: .custom(custom), customRPCs: [custom])
        let coding: JSONCoding<ProviderSettings> = .json(ProviderSettings.self)

        #expect(coding.decode(try coding.encode(settings)) == settings)
    }
}
