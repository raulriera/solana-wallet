import Foundation
import Observation
import Storage

/// The RPC provider choice, the custom RPCs, and Helius's API key that every window shares, so a change in one window
/// shows in the others and applies to the next request at once.
///
/// The store reads nothing until ``load()``. Each change shows at once and saves after the changes made before it; a
/// change that can't be saved is undone and throws. Choosing what's already chosen saves nothing. Erasing returns the
/// store to how it starts, with nothing read. The key never leaves the store except as the ``connection`` that
/// requests use, and only its first characters show.
@MainActor
@Observable
final class ProviderStore: Erasable {
    private let choice: PersistentValue<ProviderSettings>
    /// Helius's accepted key, or an empty key before one is saved.
    private let apiKey: PersistentValue<String>
    /// Whether the settings were erased since they were last read, so they show as not read until the next read.
    private var isErased = false

    /// Connects to the storage that keeps the choice and the key, without reading either.
    /// - Parameters:
    ///   - settings: The storage that keeps the provider choice and custom RPCs.
    ///   - key: The storage that keeps Helius's accepted key.
    init(settings: any ValueStoring<ProviderSettings>, key: any ValueStoring<String>) {
        choice = PersistentValue(storage: settings, empty: ProviderSettings())
        apiKey = PersistentValue(storage: key, empty: "")
    }

    /// Connects to the choice's and the key's Keychain items in a service, without reading either.
    /// - Parameter service: The Keychain service that keeps the provider items.
    convenience init(service: String) {
        self.init(settings: KeychainItem(service: service, account: "settings", coding: .json(ProviderSettings.self)),
                  key: KeychainItem(service: service, account: "api-key", coding: .utf8))
    }

    /// Whether the choice and the key were read since the store started or was erased; either one that can't be read
    /// makes both unreadable.
    var phase: PersistentValuePhase {
        if isErased { return .unloaded }
        return switch (choice.phase, apiKey.phase) {
        case (.unreadable, _), (_, .unreadable): .unreadable
        case (.loaded, .loaded): .loaded
        case (.loading, _), (_, .loading): .loading
        default: .unloaded
        }
    }

    /// Whether a read of the settings ended since the store started or was erased, even a read that failed, so work
    /// that sends requests can start; its requests then explain a failure.
    ///
    /// Work that waits for it stops when a reset erases the settings, instead of starting again and reading them anew.
    var isRead: Bool { phase == .loaded || phase == .unreadable }

    /// The choice and custom RPCs with every change made so far, or `nil` until they're read, so no provider shows as
    /// in use; before anything is saved, Solana's public RPC is in use.
    var settings: ProviderSettings? { phase == .loaded ? choice.value : nil }

    /// The saved key with all but its first characters masked, or `nil` when no key is saved or it isn't read.
    var keyPreview: String? { key?.formatted(.masked) }

    /// Where portfolios, private balances, and transactions send requests, with the key they need, or `nil` until the
    /// settings are read and while Helius is chosen without a saved key.
    ///
    /// It changes only when requests go to another provider or with a new key; an edit that keeps it, such as a new
    /// key while another provider is in use, leaves it equal.
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

    /// Reads the choice and the key, unless they were already read, and returns once the changes made before this call
    /// are saved or undone.
    func load() async {
        async let settings: Void = choice.load()
        async let key: Void = apiKey.load()
        _ = await (settings, key)
        isErased = false
    }

    /// Reads the settings, unless they were already read, and returns them with every change made so far, without
    /// waiting for those changes to save.
    /// - Returns: The provider choice and custom RPCs.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the choice or the key can't be read.
    func loadedSettings() async throws -> ProviderSettings {
        if settings == nil { await load() }
        guard let settings else { throw ProviderClientError.settingsUnreadable }
        return settings
    }

    /// Reads the settings, unless they were already read, and returns where the next request goes, with every change
    /// made so far.
    /// - Returns: The connection for the next request.
    /// - Throws: ``ProviderClientError/missingKey`` when Helius is chosen without a saved key,
    ///   ``ProviderClientError/settingsUnreadable`` when the choice or the key can't be read, or `CancellationError`;
    ///   a cancelled read is never reported as a missing key.
    func loadedConnection() async throws -> ProviderClient.Endpoint {
        _ = try await loadedSettings()
        guard let connection else {
            try Task.checkCancellation()
            throw ProviderClientError.missingKey
        }
        return connection
    }

    /// Chooses the provider that every window uses.
    ///
    /// Helius needs a saved key first, even when it's in use. An unlisted custom RPC changes nothing.
    /// - Parameter provider: The provider to use.
    /// - Throws: ``ProviderClientError/missingKey`` for Helius without a saved key, which changes nothing,
    ///   ``ProviderClientError/settingsUnreadable`` when the settings can't be read, `CancellationError` before a
    ///   change, or a storage error after undoing the change.
    func select(_ provider: ProviderSettings.Provider) async throws {
        _ = try await loadedSettings()
        // Helius can't load anything without its key, so every window would lose its holdings.
        if provider == .helius, key == nil {
            try Task.checkCancellation()
            throw ProviderClientError.missingKey
        }
        try await update { $0.select(provider) }
    }

    /// Adds a checked custom RPC and chooses it for every window; adding a listed RPC only chooses it.
    /// - Parameter url: The checked HTTPS RPC URL.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    func add(_ url: URL) async throws {
        try await update { $0.add(url) }
    }

    /// Deletes a custom RPC; deleting the RPC in use switches every window to Solana, and an unlisted URL changes
    /// nothing.
    /// - Parameter url: The RPC URL to delete.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    func remove(_ url: URL) async throws {
        try await update { $0.remove(url) }
    }

    /// Reads the settings first, unless they were already read, so the change shows and every observer hears of it,
    /// then changes the choice or the custom RPCs.
    /// - Parameter change: Changes the settings; it must give the same result each time it runs on the same value.
    /// - Throws: ``ProviderClientError/settingsUnreadable`` when the settings can't be read, or a storage error after
    ///   undoing the change.
    private func update(_ change: @escaping @Sendable (inout ProviderSettings) -> Void) async throws {
        _ = try await loadedSettings()
        try await choice.update(change)
    }

    /// Saves Helius's accepted key in place of any saved key; the provider in use stays.
    ///
    /// The settings are read first if they weren't yet, so the key shows; a key saves even when they can't be read.
    /// - Parameter key: The key that Helius accepted, without surrounding whitespace.
    /// - Throws: A storage error after undoing the change.
    func save(key: String) async throws {
        await load()
        try await apiKey.update { $0 = key }
    }

    /// Deletes the saved key and then the choice and custom RPCs after the changes made before them, and shows them as
    /// not read until the next read, which finds Solana's public RPC without a key.
    ///
    /// A reset erases the settings, so nothing that observes the connection takes the erasure for a new provider.
    /// - Throws: A storage error, which keeps what isn't deleted yet.
    func erase() async throws {
        // Not read from the start, so observers never see the emptied settings as a change.
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

nonisolated extension ProviderClient.Endpoint {
    /// Whether a connection replaces one that requests already went through.
    ///
    /// Reading the settings isn't a new connection, because nothing went through one yet, and neither is erasing them,
    /// as a reset does.
    /// - Parameters:
    ///   - connection: The connection now, or `nil` while the settings aren't read.
    ///   - previous: The connection before, or `nil` while the settings weren't read.
    /// - Returns: Whether both connections are known and differ.
    static func isNew(_ connection: Self?, after previous: Self?) -> Bool {
        guard let connection, let previous else { return false }
        return connection != previous
    }
}
