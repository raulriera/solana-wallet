import SwiftUI

extension EnvironmentValues {
    /// Reads and saves the currency choice that every window shares; `nil` where nothing can change it, as in previews.
    @Entry var currencySelection: CurrencySelection?
}
