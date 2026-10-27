import SwiftUI

/// Reads Currency's choice and keeps the rate source's currencies current while a Currency screen is on screen, runs
/// each change, and presents failures.
///
/// Each Currency screen attaches it, because a screen pushed on iPhone merges into the settings stack, where the
/// screen below stops its tasks.
private struct CurrencyLifecycle: ViewModifier {
    @Environment(CurrencyStore.self) private var store
    @Bindable var choice: CurrencySettingsModel
    let list: CurrencyListModel

    /// Reads the choice, loads the source's currencies, and awaits one change at a time.
    /// - Parameter content: A Currency screen.
    /// - Returns: The screen with managed reads, changes, and failure presentation.
    func body(content: Content) -> some View {
        let source = store.settings?.rateSource
        let attempt = choice.attempt
        content
            // Every window observes the store, so one read shows every later change.
            .task { await choice.load(from: store) }
            .task(id: CurrenciesRequest(source: source, retry: list.retry)) { await list.load(source, from: store) }
            .task(id: attempt) { await choice.run(attempt, with: store) }
            .errorAlert($choice.error)
    }

    /// What the currencies load for: a new rate source, or a retry after a failure.
    private struct CurrenciesRequest: Equatable {
        let source: CurrencySettings.RateSource?
        let retry: Int
    }
}

extension CurrencyScreen {
    /// Runs Currency's reads and changes while this screen is on screen.
    /// - Returns: The screen with managed reads, changes, and failure presentation.
    func currencyLifecycle() -> some View {
        modifier(CurrencyLifecycle(choice: choice, list: list))
    }
}

extension CurrencyListScreen {
    /// Runs Currency's reads and changes while this screen is on screen.
    /// - Returns: The screen with managed reads, changes, and failure presentation.
    func currencyLifecycle() -> some View {
        modifier(CurrencyLifecycle(choice: choice, list: list))
    }
}
