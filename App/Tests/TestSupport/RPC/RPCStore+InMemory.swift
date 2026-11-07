@testable import widgets

extension RPCStore {
    static func inMemory(_ settings: StoredValue<RPCSettings> = StoredValue(),
                         key: StoredValue<String> = StoredValue()) -> RPCStore {
        RPCStore(settings: settings, key: key)
    }

    static func inMemory(selection: RPCSettings.Provider, key: String? = nil) -> RPCStore {
        inMemory(StoredValue(RPCSettings(selection: selection)), key: StoredValue(key))
    }
}
