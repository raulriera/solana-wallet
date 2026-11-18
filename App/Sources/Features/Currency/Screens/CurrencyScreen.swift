import SwiftUI

/// Chooses the source of exchange rates and the currency that values show in.
struct CurrencyScreen: View {
    @Environment(\.palette) private var palette
    /// The currency choice, or `nil` until it's read.
    let settings: CurrencySettings?
    let choice: CurrencySettingsModel
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

            Section {
                ForEach(CurrencySettings.RateSource.allCases, id: \.self) { rateSource in
                    Button(rateSource.name) { choice.select(rateSource) }
                        .checked(isRead && source == rateSource)
                }
                Button("USD Only") { choice.select(nil) }
                    .checked(isRead && source == nil)
            } header: {
                Text("Exchange Rate Source", comment: "Header of the rate source choices in Settings > Currency.")
            } footer: {
                Text("The European Central Bank updates its rates once each working day, and Coinbase through the day. USD Only shows prices in US dollars, as they come.",
                     comment: "Footer under the rate source choices in Settings > Currency.")
                    .foregroundStyle(palette.secondaryText)
            }

            if source != nil {
                Section {
                    NavigationLink(value: CurrencyRoute.currencies) {
                        LabeledContent {
                            settings?.currencyCode.map { Text($0, format: .currencyName) }
                                ?? Text("Automatic (\(list.automaticCurrency, format: .currencyName))",
                                        comment: "The currency choice that follows the device's region. The variable is the currency's name, such as Euro.")
                        } label: {
                            Text("Currency", comment: "The row in Settings > Currency that opens the list of currencies.")
                        }
                    }
                }
            }
        }
        .formStyle(.choices)
        .animation(.default, value: source != nil)
        .navigationTitle("Currency")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CurrencyScreen(settings: CurrencySettings(rateSource: .europeanCentralBank), choice: CurrencySettingsModel(),
                       list: CurrencyListModel())
    }
}
