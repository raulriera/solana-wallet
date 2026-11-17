import Foundation
import Storage
import Testing
@testable import widgets

struct PriceSettingsTests {
    @Test
    func `A custom server shows only its host`() {
        #expect(String(localized: PriceSettings.Provider.custom(Self.server).name) == "prices.example.com")
    }

    @Test
    func `Adding a server lists and chooses it`() throws {
        let listed = try #require(URL(string: "https://one.example.com"))
        let added = try #require(URL(string: "https://two.example.com"))
        var settings = PriceSettings(selection: .off, customServers: [listed])

        settings.add(added)

        #expect(settings == PriceSettings(selection: .custom(added), customServers: [listed, added]))
    }

    @Test
    func `Adding a listed server only chooses it`() throws {
        let listed = try #require(URL(string: "https://one.example.com"))
        var settings = PriceSettings(customServers: [listed])

        settings.add(listed)

        #expect(settings == PriceSettings(selection: .custom(listed), customServers: [listed]))
    }

    @Test
    func `An unlisted server can't be chosen`() throws {
        let unlisted = try #require(URL(string: "https://one.example.com"))
        var settings = PriceSettings(selection: .off)

        settings.select(.custom(unlisted))

        #expect(settings == PriceSettings(selection: .off))
    }

    @Test(arguments: [(PriceSettings.Provider.jupiter, PriceSettings.Provider.off), (.off, .jupiter)])
    func `Built-in choices need no list`(from previous: PriceSettings.Provider, to provider: PriceSettings.Provider) {
        var settings = PriceSettings(selection: previous)

        settings.select(provider)

        #expect(settings == PriceSettings(selection: provider))
    }

    @Test
    func `Removing the server in use chooses Jupiter`() throws {
        let removed = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        var settings = PriceSettings(selection: .custom(removed), customServers: [removed, kept])

        settings.remove(removed)

        #expect(settings == PriceSettings(selection: .jupiter, customServers: [kept]))
    }

    @Test
    func `Removing another server keeps the choice`() throws {
        let removed = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        var settings = PriceSettings(selection: .custom(kept), customServers: [removed, kept])

        settings.remove(removed)

        #expect(settings == PriceSettings(selection: .custom(kept), customServers: [kept]))
    }

    nonisolated static let server = URL(string: "https://prices.example.com/v1?key=fixture-key")!
}
