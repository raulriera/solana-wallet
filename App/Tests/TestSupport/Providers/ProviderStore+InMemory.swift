import Foundation
@testable import widgets

extension ProviderStore {
    static func inMemory(_ settings: StoredValue<ProviderSettings> = StoredValue(),
                         key: StoredValue<String> = StoredValue(),
                         prices: StoredValue<PriceSettings> = StoredValue()) -> ProviderStore {
        ProviderStore(settings: settings, key: key, prices: prices)
    }

    static func inMemory(prices selection: PriceSettings.Provider) -> ProviderStore {
        let servers: [URL] = if case .custom(let url) = selection { [url] } else { [] }
        return inMemory(prices: StoredValue(PriceSettings(selection: selection, customServers: servers)))
    }

    static func inMemory(selection: ProviderSettings.Provider, key: String? = nil) -> ProviderStore {
        inMemory(StoredValue(ProviderSettings(selection: selection)), key: StoredValue(key))
    }
}
