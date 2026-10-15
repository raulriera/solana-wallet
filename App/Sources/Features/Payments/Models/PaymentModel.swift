import Foundation
import Observation

/// Owns one payment's amount: the keys typed on the keypad, the token it moves, and the unit it's typed in.
@MainActor
@Observable
final class PaymentModel {
    /// What the keypad types in.
    nonisolated enum Unit: Hashable, Sendable {
        /// The person's currency, converted to tokens at the token's price.
        case currency
        /// The token itself.
        case token
    }

    /// The tokens the account can pay with.
    let tokens: [PaymentToken]
    /// The ISO code of the person's currency.
    let currencyCode: String
    /// The token the payment moves.
    private(set) var token: PaymentToken
    /// What the keypad types in; tokens without a price are always typed as tokens.
    private(set) var unit: Unit
    /// The amount typed on the keypad.
    private(set) var entry: AmountEntry
    /// Counts key presses, accepted or not, so each one can be announced.
    private(set) var pressCount = 0
    /// Why the last key or conversion left the amount as it was, until the next accepted key.
    private(set) var rejection: AmountRejection?
    /// Counts rejected keys and conversions, so each one signals again while the same rejection stays.
    private(set) var rejectionCount = 0

    /// Starts an empty amount in the first token, typed in the person's currency when the token has a price.
    /// - Precondition: `tokens` isn't empty.
    /// - Parameters:
    ///   - tokens: The tokens the account can pay with; the first one is selected.
    ///   - currencyCode: The ISO code of the person's currency.
    init(tokens: [PaymentToken], currencyCode: String) {
        let token = tokens[0]
        let unit = token.price == nil ? Unit.token : .currency
        self.tokens = tokens
        self.currencyCode = currencyCode
        self.token = token
        self.unit = unit
        entry = AmountEntry(maximumFractionDigits: Self.fractionDigits(of: unit, token: token, currencyCode: currencyCode))
    }

    /// The token quantity the amount comes to, rounded down to the token's decimals.
    var quantity: Decimal {
        switch unit {
        case .token: entry.value
        case .currency: quantity(worth: entry.value)
        }
    }

    /// The amount's worth in the person's currency, or `nil` when the token has no price.
    var value: Decimal? {
        switch unit {
        case .currency: entry.value
        case .token: token.price.map { entry.value * $0 }
        }
    }

    /// What the typed amount counts, for showing it.
    var entryUnit: AmountEntryFormatStyle.Unit {
        switch unit {
        case .currency: .currency(code: currencyCode)
        case .token: .token(symbol: token.symbol)
        }
    }

    /// Whether the amount is more than the account holds.
    var exceedsBalance: Bool { quantity > token.balance }

    /// Whether the amount can be sent: more than zero and no more than the balance.
    var canSend: Bool { quantity > 0 && !exceedsBalance }

    /// The token to pay with, as a picker edits it.
    ///
    /// A currency amount carries over to another token with a price; otherwise the amount starts again in the new
    /// token.
    var tokenChoice: PaymentToken {
        get { token }
        set { select(newValue) }
    }

    /// The unit to type in, as a picker edits it.
    ///
    /// Switching converts what's typed; a conversion with more whole digits than the keypad types is refused.
    var unitChoice: Unit {
        get { unit }
        set { switchUnit(to: newValue) }
    }

    /// Applies a key press; rejected keys leave the amount unchanged and are counted.
    /// - Parameter key: The pressed key.
    func press(_ key: KeypadKey) {
        if entry.press(key) {
            rejection = nil
        } else {
            reject(.key)
        }
        pressCount += 1
    }

    /// Pays with another token, keeping a currency amount when the new token has a price.
    /// - Parameter token: The token to pay with.
    private func select(_ token: PaymentToken) {
        guard token != self.token else { return }
        let keepsAmount = unit == .currency && token.price != nil
        self.token = token
        guard !keepsAmount else { return }
        unit = token.price == nil ? .token : unit
        entry = AmountEntry(maximumFractionDigits: Self.fractionDigits(of: unit, token: token, currencyCode: currencyCode))
    }

    /// Types the amount in another unit, converting what's already typed, or refuses a conversion too large to type.
    /// - Parameter unit: The unit to type in; tokens without a price stay in tokens.
    private func switchUnit(to unit: Unit) {
        guard unit != self.unit, token.price != nil else { return }
        let digits = Self.fractionDigits(of: unit, token: token, currencyCode: currencyCode)
        let converted: AmountEntry?
        switch unit {
        case .token:
            // Tokens round down, so the payment never grows.
            converted = AmountEntry(quantity, maximumFractionDigits: digits)
        case .currency:
            // A value rounds to the nearest cent and shows every cent, so switching back and forth keeps it as typed,
            // unless the nearest cent buys more tokens than were typed; then it rounds down, so the payment never grows.
            let worth = value ?? 0
            let nearest = AmountEntry(worth, maximumFractionDigits: digits, rounding: .plain, padsFraction: true)
            converted = nearest.flatMap { quantity(worth: $0.value) <= quantity ? $0 : nil }
                ?? AmountEntry(worth, maximumFractionDigits: digits, padsFraction: true)
        }
        guard let converted else {
            reject(.conversion)
            return
        }
        self.unit = unit
        entry = converted
    }

    /// The token quantity a value in the person's currency buys, rounded down to the token's decimals.
    /// - Parameter value: The value in the person's currency.
    /// - Returns: The quantity, or zero when the token has no price.
    private func quantity(worth value: Decimal) -> Decimal {
        guard let price = token.price, price > 0 else { return 0 }
        var exact = value / price
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, token.decimals, .down)
        return rounded
    }

    /// Records why the amount stayed as it was, so the screen can signal it again even for the same reason.
    /// - Parameter rejection: Why the amount didn't change.
    private func reject(_ rejection: AmountRejection) {
        self.rejection = rejection
        rejectionCount += 1
    }

    /// How many fraction digits a unit allows.
    /// - Parameters:
    ///   - unit: The unit the keypad types in.
    ///   - token: The selected token.
    ///   - currencyCode: The ISO code of the person's currency.
    /// - Returns: The token's decimals, or the currency's minor units, such as 2 for dollars or 0 for yen.
    private static func fractionDigits(of unit: Unit, token: PaymentToken, currencyCode: String) -> Int {
        switch unit {
        case .token:
            return token.decimals
        case .currency:
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
            return formatter.maximumFractionDigits
        }
    }
}
