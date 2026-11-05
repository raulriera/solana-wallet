import Foundation
import Observation
import Storage

/// The RPC provider choice, the custom RPCs, and Helius's API key.
@MainActor
@Observable
final class RPCStore: Erasable {
    private let choice: PersistentValue<RPCSettings>
    /// Helius's accepted key, or an empty key before one is saved.
    private let apiKey: PersistentValue<String>
    /// Whether the settings were erased since they were last read.
    private var isErased = false

    /// Creates a store over the storage for the choice and the key, without reading either.
    ///
    /// - Parameters:
    ///   - settings: The storage that keeps the provider choice and custom RPCs.
    ///   - key: The storage that keeps Helius's accepted key.
    init(settings: any ValueStoring<RPCSettings>, key: any ValueStoring<String>) {
        choice = PersistentValue(storage: settings, empty: RPCSettings())
        apiKey = PersistentValue(storage: key, empty: "")
    }

    /// Creates a store over Keychain items in a service, without reading them.
    ///
    /// - Parameter service: The Keychain service that keeps the provider items.
    convenience init(service: String) {
        self.init(settings: KeychainItem(service: service, account: "settings", coding: .json(RPCSettings.self)),
                  key: KeychainItem(service: service, account: "api-key", coding: .utf8))
    }

    /// The read phase of the choice and the key together.
    var phase: PersistentValuePhase {
        if isErased { return .unloaded }
        return switch (choice.phase, apiKey.phase) {
        case (.unreadable, _), (_, .unreadable): .unreadable
        case (.loaded, .loaded): .loaded
        case (.loading, _), (_, .loading): .loading
        default: .unloaded
        }
    }

    /// Whether a read of the settings ended, even one that failed.
    var isRead: Bool { phase == .loaded || phase == .unreadable }

    /// The choice and custom RPCs with every change made so far, or `nil` until they're read.
    var settings: RPCSettings? { phase == .loaded ? choice.value : nil }

    /// The saved key with all but its first characters masked, or `nil` when no key is saved or it isn't read.
    var keyPreview: String? { key?.formatted(.masked) }

    /// The endpoint for requests, or `nil` before a read or while Helius is chosen without a saved key.
    var connection: SelectedRPCProvider.Endpoint? {
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

    /// Reads the choice and the key unless they were already read.
    func load() async {
        async let settings: Void = choice.load()
        async let key: Void = apiKey.load()
        _ = await (settings, key)
        isErased = false
    }

    /// Returns the settings, reading them first if needed.
    ///
    /// - Returns: The provider choice and custom RPCs.
    /// - Throws: ``RPCProviderError/settingsUnreadable`` when the choice or the key can't be read.
    func loadedSettings() async throws -> RPCSettings {
        if settings == nil { await load() }
        guard let settings else { throw RPCProviderError.settingsUnreadable }
        return settings
    }

    /// Returns the connection for the next request, reading the settings first if needed.
    ///
    /// - Returns: The connection for the next request.
    /// - Throws: ``RPCProviderError/missingKey`` when Helius is chosen without a saved key,
    ///   ``RPCProviderError/settingsUnreadable`` when the choice or the key can't be read, or `CancellationError`.
    func loadedConnection() async throws -> SelectedRPCProvider.Endpoint {
        _ = try await loadedSettings()
        guard let connection else {
            try Task.checkCancellation()
            throw RPCProviderError.missingKey
        }
        return connection
    }

    /// Chooses the provider in use.
    ///
    /// - Parameter provider: The provider to use.
    /// - Throws: ``RPCProviderError/missingKey`` for Helius without a saved key,
    ///   ``RPCProviderError/settingsUnreadable`` when the settings can't be read, `CancellationError` before a
    ///   change, or a storage error after undoing the change.
    func select(_ provider: RPCSettings.Provider) async throws {
        _ = try await loadedSettings()
        if provider == .helius, key == nil {
            try Task.checkCancellation()
            throw RPCProviderError.missingKey
        }
        try await update { $0.select(provider) }
    }

    /// Adds a checked custom RPC and chooses it.
    ///
    /// - Parameter url: The checked HTTPS RPC URL.
    /// - Throws: ``RPCProviderError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    func add(_ url: URL) async throws {
        try await update { $0.add(url) }
    }

    /// Deletes a custom RPC, choosing Solana if it was in use.
    ///
    /// - Parameter url: The RPC URL to delete.
    /// - Throws: ``RPCProviderError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    func remove(_ url: URL) async throws {
        try await update { $0.remove(url) }
    }

    /// Changes the choice or the custom RPCs, reading the settings first if needed.
    ///
    /// - Parameter change: A change to the settings that gives the same result on each run.
    /// - Throws: ``RPCProviderError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    private func update(_ change: @escaping @Sendable (inout RPCSettings) -> Void) async throws {
        _ = try await loadedSettings()
        try await choice.update(change)
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
        } catch {
            isErased = false
            throw error
        }
    }
}
