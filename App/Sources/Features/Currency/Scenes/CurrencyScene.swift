import SwiftUI

/// Owns Currency: its navigation, which pushes the rate source's currencies, and the screens' changes and currencies.
struct CurrencyScene: View {
    @Environment(CurrencyStore.self) private var store
    @State private var choice = CurrencySettingsModel()
    @State private var list = CurrencyListModel()

    var body: some View {
        let settings = store.settings
        NavigationStack {
            CurrencyScreen(settings: settings, choice: choice, list: list)
                .currencyLifecycle()
                .navigationDestination(for: CurrencyRoute.self) { route in
                    switch route {
                    case .currencies:
                        CurrencyListScreen(settings: settings, choice: choice, list: list)
                            .currencyLifecycle()
                    }
                }
        }
    }
}
