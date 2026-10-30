import SwiftUI

/// Loads the currency choice and the rate source's currencies, runs each change, and presents errors.
private struct CurrencyLifecycle: ViewModifier {
    @Environment(CurrencyStore.self) private var store
    @Bindable var choice: CurrencySettingsModel
    let list: CurrencyListModel

    func body(content: Content) -> some View {
        let source = store.settings?.rateSource
        let attempt = choice.attempt
        content
            .task { await choice.load(from: store) }
            .task(id: CurrenciesRequest(source: source, retry: list.retry)) { await list.load(source, from: store) }
            .task(id: attempt) { await choice.run(attempt, with: store) }
            .errorAlert($choice.error)
    }

    /// The rate source and retry count that the currencies load for.
    private struct CurrenciesRequest: Equatable {
        let source: CurrencySettings.RateSource?
        let retry: Int
    }
}

extension CurrencyScreen {
    /// Loads the currency choice and currencies, runs each change, and presents errors.
    ///
    /// - Returns: The screen with the Currency lifecycle.
    func currencyLifecycle() -> some View {
        modifier(CurrencyLifecycle(choice: choice, list: list))
    }
}

extension CurrencyListScreen {
    /// Loads the currency choice and currencies, runs each change, and presents errors.
    ///
    /// - Returns: The screen with the Currency lifecycle.
    func currencyLifecycle() -> some View {
        modifier(CurrencyLifecycle(choice: choice, list: list))
    }
}
