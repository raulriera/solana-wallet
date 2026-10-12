import Observation
import SwiftUI
import Testing
@testable import widgets

/// Runs Providers' lifecycle in a real window, so its key sheet presents, saves, and closes as it does on screen.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProvidersLifecycleTests {
    /// Choosing Helius without a key opens key entry; the saved key closes the sheet and Helius is chosen.
    /// - Throws: A test prerequisite error.
    @Test
    func `Saving the key that a choice asked for chooses Helius`() async throws {
        let providers = ProvidersFlow.inMemory(settings: StoredValue(ProviderSettings(selection: .solana)),
                                               providerKey: StoredValue())
        let hosted = try HostedWindow(Color.clear.modifier(ProvidersLifecycle(flow: providers)))
        defer { hosted.close() }
        providers.select(.helius)
        try #require(try await hosted.presentsViewController())
        let keyEntry = try #require(providers.keyEntry)

        keyEntry.submit("fixture-key")

        // The suite's time limit ends the wait if Helius is never chosen.
        for await selection in Observations({ providers.selection }) where selection == .helius { break }
        #expect(try await hosted.closesPresentedViewController())
    }
}
