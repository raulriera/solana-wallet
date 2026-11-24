import Foundation
@testable import widgets

extension RPCStore {
    static func inMemory(_ settings: StoredValue<RPCSettings> = StoredValue(),
                         key: StoredValue<String> = StoredValue()) -> RPCStore {
        RPCStore(settings: settings, key: key)
    }

    static func inMemory(selection: RPCSettings.Provider, key: String? = nil) -> RPCStore {
        let listed: [URL] = if case .custom(let url) = selection { [url] } else { [] }
        return inMemory(StoredValue(RPCSettings(selection: selection, customRPCs: listed)), key: StoredValue(key))
    }
}
