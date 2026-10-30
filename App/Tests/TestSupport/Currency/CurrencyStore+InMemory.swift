@testable import widgets

extension CurrencyStore {
    static func inMemory(_ storage: StoredValue<CurrencySettings> = StoredValue(),
                         http: HTTPResponses = .currency()) -> CurrencyStore {
        CurrencyStore(storage: storage, rates: CurrencyResponses.rates(http))
    }
}
