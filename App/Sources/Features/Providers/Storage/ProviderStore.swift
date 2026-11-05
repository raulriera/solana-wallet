import Foundation
import Observation
import Storage

/// The RPC provider choice, the custom RPCs, Helius's API key, and the price provider choice.
@MainActor
@Observable
final class ProviderStore: Erasable {
    private let choice: PersistentValue<ProviderSettings>
    /// Helius's accepted key, or an empty key before one is saved.
    private let apiKey: PersistentValue<String>
    private let priceChoice: PersistentValue<PriceSettings>
    /// Whether the settings were erased since they were last read.
    private var isErased = false

    /// Creates a store over the storage for the choices and the key, without reading them.
    ///
    /// - Parameters:
    ///   - settings: The storage that keeps the provider choice and custom RPCs.
    ///   - key: The storage that keeps Helius's accepted key.
    ///   - prices: The storage that keeps the price provider choice and custom price servers.
    init(settings: any ValueStoring<ProviderSettings>, key: any ValueStoring<String>,
         prices: any ValueStoring<PriceSettings>) {
        choice = PersistentValue(storage: settings, empty: ProviderSettings())
        apiKey = PersistentValue(storage: key, empty: "")
        priceChoice = PersistentValue(storage: prices, empty: PriceSettings())
    }

    /// Creates a store over Keychain items in a service, without reading them.
    ///
    /// - Parameter service: The Keychain service that keeps the provider items.
    convenience init(service: String) {
        self.init(settings: KeychainItem(service: service, account: "settings", coding: .json(ProviderSettings.self)),
                  key: KeychainItem(service: service, account: "api-key", coding: .utf8),
                  prices: KeychainItem(service: service, account: "prices", coding: .json(PriceSettings.self)))
    }

    /// The read phase of the choices and the key together.
    var phase: PersistentValuePhase {
        if isErased { return .unloaded }
        let phases = [choice.phase, apiKey.phase, priceChoice.phase]
        if phases.contains(.unreadable) { return .unreadable }
        if phases.allSatisfy({ $0 == .loaded }) { return .loaded }
        return phases.contains(.loading) ? .loading : .unloaded
    }

    /// Whether a read of the settings ended, even one that failed.
    var isRead: Bool { phase == .loaded || phase == .unreadable }

    /// The choice and custom RPCs with every change made so far, or `nil` until they're read.
    var settings: ProviderSettings? { phase == .loaded ? choice.value : nil }

    /// The price provider choice and custom price servers with every change made so far, or `nil` until they're read.
    var priceSettings: PriceSettings? { phase == .loaded ? priceChoice.value : nil }

    /// The saved key with all but its first characters masked, or `nil` when no key is saved or it isn't read.
    var keyPreview: String? { key?.formatted(.masked) }

    /// The endpoint for requests, or `nil` before a read or while Helius is chosen without a saved key.
    var connection: ProviderClient.Endpoint? {
        switch settings?.selection {
        case .solana: .solana
        case .helius: key.map { .helius(key: $0) }
        case .custom(let url): .custom(url)
        case nil: nil
        }
    }

    /// The saved key, or `nil` when no key is saved or it isn't read.
    private var key: String? {
        guard phase == .loaded, !apiKey.value.isEmpty else { return nil }
        return apiKey.value
    }

    /// Reads the choices and the key unless they were already read.
    func load() async {
        async let settings: Void = choice.load()
        async let key: Void = apiKey.load()
        async let prices: Void = priceChoice.load()
        _ = await (settings, key, prices)
        isErased = false
    }

    /// Returns the settings, reading them first if needed.
    ///
    /// - Returns: The provider choice and custom RPCs.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the choices or the key can't be read.
    func loadedSettings() async throws -> ProviderSettings {
        if settings == nil { await load() }
        guard let settings else { throw ProviderClientError.settingsUnreadable }
        return settings
    }

    /// Returns the price provider choice and custom price servers, reading the settings first if needed.
    ///
    /// - Returns: The price provider choice and custom price servers.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the choices or the key can't be read.
    func loadedPriceSettings() async throws -> PriceSettings {
        _ = try await loadedSettings()
        return priceChoice.value
    }

    /// Returns the connection for the next request, reading the settings first if needed.
    ///
    /// - Returns: The connection for the next request.
    /// - Throws: ``ProviderClientError/missingKey`` when Helius is chosen without a saved key,
    ///   ``ProviderClientError/settingsUnreadable`` when the choice or the key can't be read, or `CancellationError`.
    func loadedConnection() async throws -> ProviderClient.Endpoint {
        _ = try await loadedSettings()
        guard let connection else {
            try Task.checkCancellation()
            throw ProviderClientError.missingKey
        }
        return connection
    }

    /// Chooses the provider in use.
    ///
    /// - Parameter provider: The provider to use.
    /// - Throws: ``ProviderClientError/missingKey`` for Helius without a saved key,
    ///   ``ProviderClientError/settingsUnreadable`` when the settings can't be read, `CancellationError` before a
    ///   change, or a storage error after undoing the change.
    func select(_ provider: ProviderSettings.Provider) async throws {
        _ = try await loadedSettings()
        if provider == .helius, key == nil {
            try Task.checkCancellation()
            throw ProviderClientError.missingKey
        }
        try await update(choice) { $0.select(provider) }
    }

    /// Adds a checked custom RPC and chooses it.
    ///
    /// - Parameter url: The checked HTTPS RPC URL.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    func add(_ url: URL) async throws {
        try await update(choice) { $0.add(url) }
    }

    /// Deletes a custom RPC, choosing Solana if it was in use.
    ///
    /// - Parameter url: The RPC URL to delete.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    func remove(_ url: URL) async throws {
        try await update(choice) { $0.remove(url) }
    }

    /// Chooses the price provider in use.
    ///
    /// - Parameter provider: The price provider to use; a custom server must already be in the list.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    func select(prices provider: PriceSettings.Provider) async throws {
        try await update(priceChoice) { $0.select(provider) }
    }

    /// Adds a checked custom price server and chooses it.
    ///
    /// - Parameter url: The checked HTTPS price server URL.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    func add(priceServer url: URL) async throws {
        try await update(priceChoice) { $0.add(url) }
    }

    /// Deletes a custom price server, choosing Jupiter if it was in use.
    ///
    /// - Parameter url: The price server URL to delete.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    func remove(priceServer url: URL) async throws {
        try await update(priceChoice) { $0.remove(url) }
    }

    /// Changes one of the choices, reading the settings first if needed.
    ///
    /// - Parameters:
    ///   - item: The choice to change.
    ///   - change: A change to the choice that gives the same result on each run.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    private func update<Value>(_ item: PersistentValue<Value>,
                               with change: @escaping @Sendable (inout Value) -> Void) async throws {
        _ = try await loadedSettings()
        try await item.update(change)
    }

    /// Saves Helius's accepted key in place of any saved key.
    ///
    /// - Parameter key: The key that Helius accepted, without surrounding whitespace.
    /// - Throws: A storage error after undoing the change.
    func save(key: String) async throws {
        await load()
        try await apiKey.update { $0 = key }
    }

    func erase() async throws {
        isErased = true
        do {
            try await apiKey.erase()
            try await choice.erase()
            try await priceChoice.erase()
        } catch {
            isErased = false
            throw error
        }
    }
}
