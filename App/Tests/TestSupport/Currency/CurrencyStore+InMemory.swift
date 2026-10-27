@testable import widgets

extension CurrencyStore {
    /// Creates the shared choice over in-memory storage and the real rate adapters, without reading it.
    /// - Parameters:
    ///   - storage: The in-memory storage that keeps the choice.
    ///   - http: The fixture transport that the rate adapters share.
    /// - Returns: A store that reads nothing until it loads.
    static func inMemory(_ storage: StoredValue<CurrencySettings> = StoredValue(),
                         http: HTTPResponses = .currency()) -> CurrencyStore {
        CurrencyStore(storage: storage, rates: CurrencyResponses.rates(http))
    }
}
