import Foundation
import Testing
@testable import widgets

struct RPCSettingsTests {
    @Test
    func `A custom RPC shows only its host`() throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token?api-key=fixture-key"))

        #expect(String(localized: RPCSettings.Provider.custom(custom).name) == "rpc.example.com")
    }

    @Test
    func `Adding a listed RPC only chooses it`() throws {
        let listed = try #require(URL(string: "https://one.example.com"))
        var settings = RPCSettings(customRPCs: [listed])

        settings.add(listed)

        #expect(settings == RPCSettings(selection: .custom(listed), customRPCs: [listed]))
    }

    @Test
    func `An unlisted custom RPC can't be chosen`() throws {
        let unlisted = try #require(URL(string: "https://one.example.com"))
        var settings = RPCSettings()

        settings.select(.custom(unlisted))

        #expect(settings == RPCSettings())
    }
}
