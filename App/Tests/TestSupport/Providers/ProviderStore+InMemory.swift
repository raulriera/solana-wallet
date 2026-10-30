@testable import widgets

extension ProviderStore {
    static func inMemory(_ settings: StoredValue<ProviderSettings> = StoredValue(),
                         key: StoredValue<String> = StoredValue()) -> ProviderStore {
        ProviderStore(settings: settings, key: key)
    }

    static func inMemory(selection: ProviderSettings.Provider, key: String? = nil) -> ProviderStore {
        inMemory(StoredValue(ProviderSettings(selection: selection)), key: StoredValue(key))
    }
}
