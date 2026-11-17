import Foundation
import SwiftUI

/// Shows the price of one token in its quote currency.
struct TokenPrice: View {
    let price: Decimal
    let currency: String

    var body: some View {
        Text(price, format: .price(code: currency))
            .contentTransition(.numericText(value: price))
    }
}

#Preview {
    VStack(alignment: .trailing) {
        TokenPrice(price: 166.23, currency: "USD")
        TokenPrice(price: 0.000021, currency: "USD")
    }
}
