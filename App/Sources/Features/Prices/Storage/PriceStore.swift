import Foundation
import Observation
import Storage

/// The price provider choice and the custom price servers.
@MainActor
@Observable
final class PriceStore: Erasable {
    private let choice: PersistentValue<PriceSettings>

    /// Creates a store without reading the choice.
    ///
    /// - Parameter storage: The storage that keeps the choice and the custom price servers.
    init(storage: any ValueStoring<PriceSettings>) {
        choice = PersistentValue(storage: storage, empty: PriceSettings())
    }

    /// Creates a store over a Keychain item in a service, without reading it.
    ///
    /// - Parameter service: The Keychain service that keeps the choice.
    convenience init(service: String) {
        self.init(storage: KeychainItem(service: service, account: "settings", coding: .json(PriceSettings.self)))
    }

    /// The choice and custom price servers with every change made so far, or `nil` until they're read.
    var settings: PriceSettings? { phase == .loaded ? choice.value : nil }

    var phase: PersistentValuePhase { choice.phase }

    /// Reads the choice unless it was already read.
    func load() async {
        await choice.load()
    }

    /// Returns the choice, reading it first if needed.
    ///
    /// - Returns: The price provider choice and custom price servers.
    /// - Throws: ``PricesError/settingsUnreadable`` when the choice can't be read.
    func loadedSettings() async throws -> PriceSettings {
        try await choice.loadedValue(orThrow: PricesError.settingsUnreadable)
    }

    /// Chooses the price provider in use.
    ///
    /// - Parameter provider: The price provider to use; a custom server must already be in the list.
    /// - Throws: ``PricesError/settingsUnreadable`` when the choice can't be read, or a storage error after undoing
    ///   the change.
    func select(_ provider: PriceSettings.Provider) async throws {
        try await update { $0.select(provider) }
    }

    /// Adds a checked custom price server and chooses it.
    ///
    /// - Parameter url: The checked HTTPS price server URL.
    /// - Throws: ``PricesError/settingsUnreadable`` when the choice can't be read, or a storage error after undoing
    ///   the change.
    func add(_ url: URL) async throws {
        try await update { $0.add(url) }
    }

    /// Deletes a custom price server, choosing Jupiter if it was in use.
    ///
    /// - Parameter url: The price server URL to delete.
    /// - Throws: ``PricesError/settingsUnreadable`` when the choice can't be read, or a storage error after undoing
    ///   the change.
    func remove(_ url: URL) async throws {
        try await update { $0.remove(url) }
    }

    func erase() async throws {
        try await choice.forget()
    }

    /// Changes the choice or the custom price servers, reading them first if needed.
    ///
    /// - Parameter change: A change to the settings that gives the same result on each run.
    /// - Throws: ``PricesError/settingsUnreadable`` when the choice can't be read, or a storage error after undoing
    ///   the change.
    private func update(_ change: @escaping @Sendable (inout PriceSettings) -> Void) async throws {
        _ = try await loadedSettings()
        try await choice.update(change)
    }
}
