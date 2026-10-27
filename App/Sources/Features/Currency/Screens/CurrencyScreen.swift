import SwiftUI

/// Chooses where exchange rates come from and the currency that every window shows values in.
struct CurrencyScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.locale) private var locale
    /// The choice that every window shares, or `nil` until it's read, so nothing shows as chosen.
    let settings: CurrencySettings?
    /// Runs each change to the choice.
    let choice: CurrencySettingsModel
    /// The rate source's currencies, which name the currency that an automatic choice follows.
    let list: CurrencyListModel

    var body: some View {
        let isRead = settings != nil
        let source = settings?.rateSource
        Form {
            Section {
                TitleCardContent(
                    title: "Currency",
                    message: "Show values in your currency. Prices convert with exchange rates from the source you choose.",
                    systemImage: "banknote.fill"
                )
            }
            .listRowBackground(palette.surface)

            Section {
                ForEach(CurrencySettings.RateSource.allCases, id: \.self) { rateSource in
                    Button(rateSource.name) { choice.select(rateSource) }
                        .buttonStyle(.choice(isSelected: isRead && source == rateSource))
                }
                Button("USD Only") { choice.select(nil) }
                    .buttonStyle(.choice(isSelected: isRead && source == nil))
            } header: {
                Text("Exchange Rate Source", comment: "Header of the rate source choices in Settings > Currency.")
            } footer: {
                Text("The European Central Bank updates its rates once each working day, and Coinbase through the day. USD Only shows prices in US dollars, as they come.",
                     comment: "Footer under the rate source choices in Settings > Currency.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
            .listRowSeparatorTint(palette.separator)

            if source != nil {
                Section {
                    NavigationLink(value: CurrencyRoute.currencies) {
                        LabeledContent {
                            Text(settings?.currencyCode.map { locale.localizedString(forCurrencyCode: $0) ?? $0 } ?? automaticName)
                        } label: {
                            Text("Currency", comment: "The row in Settings > Currency that opens the list of currencies.")
                        }
                    }
                }
                .listRowBackground(palette.surface)
            }
        }
        // The currency row comes and goes with the rate source.
        .animation(.default, value: source != nil)
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
    }

    /// The automatic choice with the currency it resolves to.
    private var automaticName: String {
        let code = list.automaticCurrency
        return String(localized: "Automatic (\(locale.localizedString(forCurrencyCode: code) ?? code))",
                      comment: "The currency choice that follows the device's region. The variable is the currency's name, such as Euro.")
    }
}

#Preview {
    NavigationStack {
        CurrencyScreen(settings: CurrencySettings(rateSource: .europeanCentralBank), choice: CurrencySettingsModel(),
                       list: CurrencyListModel())
    }
}
