import Foundation
import Testing
@testable import widgets

/// Checks how a provider choice changes the saved settings.
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

    /// Choosing the provider in use changes nothing.
    @Test
    func `Choosing the provider in use changes nothing`() {
        var settings = ProviderSettings()

        let changed = settings.select(.helius)

        #expect(changed == false)
        #expect(settings == ProviderSettings())
    }
}
