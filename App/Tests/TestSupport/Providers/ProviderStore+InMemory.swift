@testable import widgets

extension ProviderStore {
    /// Creates the shared provider settings over in-memory storage, without reading them.
    /// - Parameters:
    ///   - settings: The in-memory storage that keeps the provider choice and custom RPCs.
    ///   - key: The in-memory storage that keeps Helius's accepted key.
    /// - Returns: A store that reads nothing until it loads.
    static func inMemory(_ settings: StoredValue<ProviderSettings> = StoredValue(),
                         key: StoredValue<String> = StoredValue()) -> ProviderStore {
        ProviderStore(settings: settings, key: key)
    }

    /// Creates the shared provider settings with a saved choice and an optional saved key, without reading them.
    /// - Parameters:
    ///   - selection: The saved provider choice.
    ///   - key: Helius's saved key, if any.
    /// - Returns: A store that reads nothing until it loads.
    static func inMemory(selection: ProviderSettings.Provider, key: String? = nil) -> ProviderStore {
        inMemory(StoredValue(ProviderSettings(selection: selection)), key: StoredValue(key))
    }
}
