import SwiftUI

/// Keeps Currency's choice and the rate source's currencies current while a Currency screen is on screen, runs each
/// change, and presents failures.
///
/// Each Currency screen attaches it, because a screen pushed on iPhone merges into the settings stack, where the
/// screen below stops its tasks.
private struct CurrencyLifecycle: ViewModifier {
    @Environment(\.currencySelection) private var selection
    @Bindable var choice: CurrencySettingsModel
    let list: CurrencyListModel

    /// Reads the choice whenever any window changes it, loads the source's currencies, and awaits one change at a time.
    /// - Parameter content: A Currency screen.
    /// - Returns: The screen with managed reads, changes, and failure presentation.
    func body(content: Content) -> some View {
        let source = choice.settings?.rateSource
        let attempt = choice.attempt
        content
            // Reads again after any window saves a change, so every window shows what's saved.
            .task(id: selection?.revision.value) {
                guard let selection else { return }
                await choice.reload(from: selection)
            }
            .task(id: CurrenciesRequest(source: source, retry: list.retry)) {
                guard let selection else { return }
                await list.load(source, from: selection)
            }
            .task(id: attempt) {
                guard let selection else { return }
                await choice.run(attempt, with: selection)
            }
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
