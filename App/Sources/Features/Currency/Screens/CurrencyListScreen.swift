import SwiftUI

/// Lists the rate source's currencies to choose from.
struct CurrencyListScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.locale) private var locale
    /// The currency choice, or `nil` until it's read.
    let settings: CurrencySettings?
    let choice: CurrencySettingsModel
    @Bindable var list: CurrencyListModel

    var body: some View {
        let isRead = settings != nil
        let chosen = settings?.currencyCode
        Group {
            if let error = list.error {
                ContentUnavailableView {
                    Label(error.errorDescription ?? "", systemImage: "banknote")
                } description: {
                    Text(error.recoverySuggestion ?? "")
                } actions: {
                    Button("Try Again") { list.retryLoading() }
                }
            } else if list.currencies != nil {
                Form {
                    if list.search.isEmpty {
                        Section {
                            Button {
                                choice.select(currencyCode: nil)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text("Automatic", comment: "The currency choice that follows the device's region.")
                                    Text(locale.localizedString(forCurrencyCode: list.automaticCurrency)
                                         ?? list.automaticCurrency)
                                        .font(.subheadline)
                                        .foregroundStyle(palette.secondaryText)
                                }
                            }
                            .buttonStyle(.choice(isSelected: isRead && chosen == nil))
                        }
                        .listRowBackground(palette.surface)
                        .listRowSeparatorTint(palette.separator)
                    }

                    Section {
                        ForEach(list.listed, id: \.self) { code in
                            Button {
                                choice.select(currencyCode: code)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(locale.localizedString(forCurrencyCode: code) ?? code)
                                    Text(code)
                                        .font(.subheadline)
                                        .foregroundStyle(palette.secondaryText)
                                }
                            }
                            .buttonStyle(.choice(isSelected: chosen == code))
                        }
                    }
                    .listRowBackground(palette.surface)
                    .listRowSeparatorTint(palette.separator)
                }
                .scrollContentBackground(.hidden)
                .readableContentWidth()
                .searchable(text: $list.search)
                .overlay {
                    if list.listed.isEmpty, !list.search.isEmpty { ContentUnavailableView.search(text: list.search) }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}
