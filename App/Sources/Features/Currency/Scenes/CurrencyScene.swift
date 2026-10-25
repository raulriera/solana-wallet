import SwiftUI

/// Owns Currency: its navigation, which pushes the rate source's currencies, and the screens' choice and currencies.
struct CurrencyScene: View {
    @State private var choice = CurrencySettingsModel()
    @State private var list = CurrencyListModel()

    var body: some View {
        NavigationStack {
            CurrencyScreen(choice: choice, list: list)
                .currencyLifecycle()
                .navigationDestination(for: CurrencyRoute.self) { route in
                    switch route {
                    case .currencies:
                        CurrencyListScreen(choice: choice, list: list)
                            .currencyLifecycle()
                    }
                }
        }
    }
}
