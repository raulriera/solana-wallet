import Foundation
import Testing
@testable import widgets

/// Checks that provider choices and custom RPC changes are saved before the previous provider's work ends, and that
/// windows observe again after.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderSelectionTests {
    /// The choice is saved before the portfolio ends the previous provider's work, and windows hear about it last.
    /// - Throws: A selection failure.
    @Test
    func `A new provider is saved before the previous provider's work ends and windows observe again after`() async throws {
        let settings = StoredValue(ProviderSettings(selection: .helius))
        let gate = Suspension()
        let portfolio = ProviderChanges(gate: gate)
        let revision = Revision()
        let selection = ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: portfolio, revision: revision)

        let selecting = Task { try await selection.select(.solana) }
        await gate.waitUntilStarted()
        #expect(await settings.value?.selection == .solana)
        #expect(revision.value == 0)
        gate.resume()
        try await selecting.value

        #expect(await portfolio.count == 1)
        #expect(revision.value == 1)
    }

    /// Choosing the provider in use, Solana's public RPC before anything is saved, saves nothing, keeps the portfolio's
    /// work, and doesn't restart windows.
    /// - Throws: A selection failure.
    @Test
    func `Choosing the provider in use changes nothing`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let portfolio = ProviderChanges()
        let revision = Revision()

        try await ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: portfolio, revision: revision)
            .select(.solana)

        #expect(await settings.value == nil)
        #expect(await portfolio.count == 0)
        #expect(revision.value == 0)
    }

    /// Helius needs its key before anything changes, whether or not it's already in use.
    /// - Parameter saved: The saved choice, or `nil` while Solana is in use by default.
    @Test(arguments: [nil, ProviderSettings(selection: .helius)])
    func `Helius isn't chosen without a saved key`(saved: ProviderSettings?) async {
        let settings = StoredValue(saved)
        let portfolio = ProviderChanges()
        let revision = Revision()

        await #expect(throws: ProviderClientError.missingKey) {
            try await ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: portfolio, revision: revision)
                .select(.helius)
        }

        #expect(await settings.value == saved)
        #expect(await portfolio.count == 0)
        #expect(revision.value == 0)
    }

    /// A choice of Helius cancelled before its key is found stays a cancellation, so no key entry opens later.
    @Test
    func `A cancelled choice of Helius isn't reported as a missing key`() async {
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let selection = ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: ProviderChanges(),
                                          revision: Revision())

        let selecting = Task { try await selection.select(.helius) }
        selecting.cancel()

        await #expect(throws: CancellationError.self) { try await selecting.value }
        #expect(await settings.value?.selection == .solana)
    }

    /// A saved key lets Helius replace another provider.
    /// - Throws: A selection failure.
    @Test
    func `A saved key lets Helius be chosen`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let portfolio = ProviderChanges()
        let revision = Revision()

        try await ProviderSelection(settings: settings, providerKey: StoredValue("fixture-key"), portfolio: portfolio,
                                    revision: revision).select(.helius)

        #expect(await settings.value?.selection == .helius)
        #expect(await portfolio.count == 1)
        #expect(revision.value == 1)
    }

    /// A new choice keeps the custom RPCs that are already saved.
    /// - Throws: A selection failure or a test prerequisite error.
    @Test
    func `A new provider keeps the saved custom RPCs`() async throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let settings = StoredValue(ProviderSettings(selection: .helius, customRPCs: [custom]))

        try await ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: ProviderChanges(), revision: Revision())
            .select(.solana)

        #expect(await settings.value == ProviderSettings(selection: .solana, customRPCs: [custom]))
    }

    /// A choice that can't be saved leaves the previous provider in use everywhere.
    @Test
    func `A choice that can't be saved changes nothing`() async {
        let saved = ProviderSettings(selection: .helius)
        let settings = StoredValue(saved, failsSaving: true)
        let portfolio = ProviderChanges()
        let revision = Revision()

        await #expect(throws: CocoaError.self) {
            try await ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: portfolio, revision: revision)
                .select(.solana)
        }

        #expect(await settings.value == saved)
        #expect(await portfolio.count == 0)
        #expect(revision.value == 0)
    }

    /// Saved logos that can't be removed don't undo a saved change, and windows still observe again.
    /// - Throws: A selection failure.
    @Test
    func `A change applies when saved logos can't be removed`() async throws {
        let settings = StoredValue(ProviderSettings(selection: .helius))
        let revision = Revision()
        let selection = ProviderSelection(settings: settings, providerKey: StoredValue(),
                                          portfolio: ProviderChanges(error: CocoaError(.fileWriteOutOfSpace)), revision: revision)

        try await selection.select(.solana)

        #expect(await settings.value?.selection == .solana)
        #expect(revision.value == 1)
    }

    /// A checked custom RPC is saved and chosen, the previous provider's work ends, and windows observe again.
    /// - Throws: A selection failure or a test prerequisite error.
    @Test
    func `A new custom RPC is saved and chosen`() async throws {
        let listed = try #require(URL(string: "https://one.example.com"))
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let settings = StoredValue(ProviderSettings(customRPCs: [listed]))
        let portfolio = ProviderChanges()
        let revision = Revision()

        try await ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: portfolio, revision: revision)
            .add(custom)

        #expect(await settings.value == ProviderSettings(selection: .custom(custom), customRPCs: [listed, custom]))
        #expect(await portfolio.count == 1)
        #expect(revision.value == 1)
    }

    /// Adding the custom RPC in use saves nothing, keeps the portfolio's work, and doesn't restart windows.
    /// - Throws: A selection failure or a test prerequisite error.
    @Test
    func `Adding the custom RPC in use changes nothing`() async throws {
        let custom = try #require(URL(string: "https://rpc.example.com"))
        let saved = ProviderSettings(selection: .custom(custom), customRPCs: [custom])
        let settings = StoredValue(saved)
        let portfolio = ProviderChanges()
        let revision = Revision()

        try await ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: portfolio, revision: revision)
            .add(custom)

        #expect(await settings.value == saved)
        #expect(await portfolio.count == 0)
        #expect(revision.value == 0)
    }

    /// Deleting the custom RPC in use switches every window to Solana and ends the RPC's portfolio work.
    /// - Throws: A selection failure or a test prerequisite error.
    @Test
    func `Deleting the custom RPC in use switches to Solana`() async throws {
        let deleted = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .custom(deleted), customRPCs: [deleted, kept]))
        let portfolio = ProviderChanges()
        let revision = Revision()

        try await ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: portfolio, revision: revision)
            .remove(deleted)

        #expect(await settings.value == ProviderSettings(selection: .solana, customRPCs: [kept]))
        #expect(await portfolio.count == 1)
        #expect(revision.value == 1)
    }

    /// Deleting another custom RPC keeps the provider in use and its portfolio work; windows still update their lists.
    /// - Throws: A selection failure or a test prerequisite error.
    @Test
    func `Deleting another custom RPC keeps the provider in use`() async throws {
        let deleted = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .custom(kept), customRPCs: [deleted, kept]))
        let portfolio = ProviderChanges()
        let revision = Revision()

        try await ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: portfolio, revision: revision)
            .remove(deleted)

        #expect(await settings.value == ProviderSettings(selection: .custom(kept), customRPCs: [kept]))
        #expect(await portfolio.count == 0)
        #expect(revision.value == 1)
    }

    /// Deleting an RPC that isn't listed saves nothing and tells no window.
    /// - Throws: A selection failure or a test prerequisite error.
    @Test
    func `Deleting an unlisted RPC changes nothing`() async throws {
        let unlisted = try #require(URL(string: "https://one.example.com"))
        let settings = StoredValue<ProviderSettings>()
        let portfolio = ProviderChanges()
        let revision = Revision()

        try await ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: portfolio, revision: revision)
            .remove(unlisted)

        #expect(await settings.value == nil)
        #expect(await portfolio.count == 0)
        #expect(revision.value == 0)
    }
}
