import Foundation
import Testing
@testable import widgets

/// Checks that a provider choice is saved before the previous provider's work ends, and that windows observe again after.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderSelectionTests {
    /// The choice is saved before the portfolio ends the previous provider's work, and windows hear about it last.
    /// - Throws: A selection failure.
    @Test
    func `A new provider is saved before the previous provider's work ends and windows observe again after`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let gate = Suspension()
        let portfolio = ProviderChanges(gate: gate)
        let revision = Revision()
        let selection = ProviderSelection(settings: settings, portfolio: portfolio, revision: revision)

        let selecting = Task { try await selection.select(.solana) }
        await gate.waitUntilStarted()
        #expect(await settings.value?.selection == .solana)
        #expect(revision.value == 0)
        gate.resume()
        try await selecting.value

        #expect(await portfolio.count == 1)
        #expect(revision.value == 1)
    }

    /// Choosing the provider in use saves nothing, keeps the portfolio's work, and doesn't restart windows.
    /// - Throws: A selection failure.
    @Test
    func `Choosing the provider in use changes nothing`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let portfolio = ProviderChanges()
        let revision = Revision()

        try await ProviderSelection(settings: settings, portfolio: portfolio, revision: revision).select(.helius)

        #expect(await settings.value == nil)
        #expect(await portfolio.count == 0)
        #expect(revision.value == 0)
    }

    /// A new choice keeps the custom RPCs that are already saved.
    /// - Throws: A selection failure or a test prerequisite error.
    @Test
    func `A new provider keeps the saved custom RPCs`() async throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let settings = StoredValue(ProviderSettings(customRPCs: [custom]))

        try await ProviderSelection(settings: settings, portfolio: ProviderChanges(), revision: Revision()).select(.solana)

        #expect(await settings.value == ProviderSettings(selection: .solana, customRPCs: [custom]))
    }

    /// A choice that can't be saved leaves the previous provider in use everywhere.
    @Test
    func `A choice that can't be saved changes nothing`() async {
        let settings = StoredValue<ProviderSettings>(failsSaving: true)
        let portfolio = ProviderChanges()
        let revision = Revision()

        await #expect(throws: CocoaError.self) {
            try await ProviderSelection(settings: settings, portfolio: portfolio, revision: revision).select(.solana)
        }

        #expect(await settings.value == nil)
        #expect(await portfolio.count == 0)
        #expect(revision.value == 0)
    }

    /// When saved logos can't be removed, the choice stays saved and windows still observe again.
    @Test
    func `Windows observe again when saved logos can't be removed`() async {
        let settings = StoredValue<ProviderSettings>()
        let revision = Revision()
        let selection = ProviderSelection(settings: settings, portfolio: ProviderChanges(error: CocoaError(.fileWriteOutOfSpace)),
                                          revision: revision)

        await #expect(throws: CocoaError(.fileWriteOutOfSpace)) { try await selection.select(.solana) }

        #expect(await settings.value?.selection == .solana)
        #expect(revision.value == 1)
    }
}
