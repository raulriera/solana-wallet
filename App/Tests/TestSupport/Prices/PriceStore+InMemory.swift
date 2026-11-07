import Foundation
@testable import widgets

extension PriceStore {
    static func inMemory(_ storage: StoredValue<PriceSettings> = StoredValue()) -> PriceStore {
        PriceStore(storage: storage)
    }

    static func inMemory(selection: PriceSettings.Provider) -> PriceStore {
        let servers: [URL] = if case .custom(let url) = selection { [url] } else { [] }
        return inMemory(StoredValue(PriceSettings(selection: selection, customServers: servers)))
    }
}
