import Foundation
import Storage
import Testing
@testable import widgets

struct RPCSettingsTests {
    @Test
    func `New settings select Solana without custom RPCs`() {
        let settings = RPCSettings()

        #expect(settings.selection == .solana)
        #expect(settings.customRPCs.isEmpty)
    }

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

    @Test
    func `Settings come back as they were saved`() throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token?api-key=fixture-key"))
        let settings = RPCSettings(selection: .custom(custom), customRPCs: [custom])
        let coding: JSONCoding<RPCSettings> = .json(RPCSettings.self)

        #expect(coding.decode(try coding.encode(settings)) == settings)
    }
}
