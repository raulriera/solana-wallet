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

    /// Which of the account's balances the payment spends, which the line under the amount names.
    nonisolated enum Source: Hashable, Sendable {
        /// The account's tokens, without naming a balance.
        case account
        /// The account's public balance, apart from its private balance.
        case publicBalance
        /// The account's available private balance, apart from its public balance.
        case privateBalance

        /// The line under the amount when the person has nothing to choose: the balance that the payment spends.
        /// - Parameters:
        ///   - quantity: The balance.
        ///   - token: The token that the balance counts.
        /// - Returns: The balance with its name, such as "Public balance: 1.2 SOL".
        func balance(_ quantity: Decimal, of token: PaymentToken) -> LocalizedStringResource {
            switch self {
            case .account:
                LocalizedStringResource("Balance: \(quantity, format: .quantity(of: token))",
                                        comment: "Line under a payment's amount. The variable is the balance with its symbol, such as 1.2 SOL.")
            case .publicBalance:
                LocalizedStringResource("Public balance: \(quantity, format: .quantity(of: token))",
                                        comment: "Line under the amount added to a private balance. The variable is the public balance with its symbol, such as 1.2 SOL.")
            case .privateBalance:
                LocalizedStringResource("Private balance: \(quantity, format: .quantity(of: token))",
                                        comment: "Line under the amount moved to the public balance. The variable is the available private balance with its symbol, such as 1.2 SOL.")
            }
        }

        /// The warning that replaces the line under the amount when the amount is more than the balance.
        var warning: LocalizedStringResource {
            switch self {
            case .account:
                LocalizedStringResource("More than your balance",
                                        comment: "Warning under a payment's amount when it's more than the balance.")
            case .publicBalance:
                LocalizedStringResource("More than your public balance",
                                        comment: "Warning under the amount added to a private balance when it's more than the public balance.")
            case .privateBalance:
                LocalizedStringResource("More than your private balance",
                                        comment: "Warning under the amount moved to the public balance when it's more than the available private balance.")
            }
        }

        /// Tells VoiceOver the amount after a key press, and that it's more than the balance.
        /// - Parameter amount: The formatted amount.
        /// - Returns: The amount with the warning.
        func overBalance(_ amount: String) -> LocalizedStringResource {
            switch self {
            case .account:
                LocalizedStringResource("\(amount), more than your balance",
                                        comment: "VoiceOver announcement after a key press when the amount is more than the balance. The variable is the formatted amount.")
            case .publicBalance:
                LocalizedStringResource("\(amount), more than your public balance",
                                        comment: "VoiceOver announcement after a key press when the amount added to a private balance is more than the public balance. The variable is the formatted amount.")
            case .privateBalance:
                LocalizedStringResource("\(amount), more than your private balance",
                                        comment: "VoiceOver announcement after a key press when the amount moved to the public balance is more than the available private balance. The variable is the formatted amount.")
            }
        }
    }

    /// The tokens the account can pay with, which follow its balances and prices.
    private(set) var tokens: [PaymentToken]
    /// The ISO code of the person's currency, which follows their choice.
    private(set) var currencyCode: String
    /// Which of the account's balances the payment spends.
    let source: Source
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
    /// The record of the payment that was sent with this amount, as it was sent, so the amount clears once the payment
    /// succeeds; a key press or a clear forgets it, so a later success never clears a newly typed amount.
    var submittedRecord: TransactionRecord?

    /// Starts an empty amount in the first token, typed in the person's currency when the token has a price.
    /// - Precondition: `tokens` isn't empty.
    /// - Parameters:
    ///   - tokens: The tokens the account can pay with; the first one is selected.
    ///   - currencyCode: The ISO code of the person's currency.
    ///   - source: Which of the account's balances the payment spends.
    init(tokens: [PaymentToken], currencyCode: String, source: Source = .account) {
        let token = tokens[0]
        let unit = token.price == nil ? Unit.token : .currency
        self.tokens = tokens
        self.currencyCode = currencyCode
        self.source = source
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

    /// The amount as it is now, which a review keeps while the balances and prices change.
    var amount: PaymentAmount {
        PaymentAmount(token: token, quantity: quantity, value: value, currencyCode: currencyCode)
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

    /// Whether the person can pay with another token or type the amount in another unit.
    var offersChoices: Bool { tokens.count > 1 || token.price != nil }

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
        submittedRecord = nil
        if entry.press(key) {
            rejection = nil
        } else {
            reject(.key)
        }
        pressCount += 1
    }

    /// Clears the amount after it was sent, keeping the token and the unit it's typed in, and forgets the sent
    /// payment's record.
    func clear() {
        entry = emptyEntry
        rejection = nil
        submittedRecord = nil
    }

    /// Follows the account's latest balances, prices, and currency, keeping the selected token and the amount as typed.
    ///
    /// A token that loses its price is typed in tokens, converted at its last price. An amount typed in the previous
    /// currency starts again in the new one, and when the selected token is gone, the first one is selected and the
    /// amount starts again.
    /// - Precondition: `tokens` isn't empty.
    /// - Parameters:
    ///   - tokens: The tokens the account can pay with now.
    ///   - currencyCode: The ISO code of the currency that their prices are in.
    func update(_ tokens: [PaymentToken], currencyCode: String) {
        guard tokens != self.tokens || currencyCode != self.currencyCode else { return }
        let changesCurrency = currencyCode != self.currencyCode
        self.tokens = tokens
        self.currencyCode = currencyCode
        guard let updated = tokens.first(where: { $0.id == token.id }) else {
            restart(in: tokens[0])
            return
        }
        guard !changesCurrency || unit == .token else {
            // An amount in the previous currency means nothing in the new one.
            restart(in: updated)
            return
        }
        guard updated != token else { return }
        if unit == .currency, updated.price == nil {
            // Converted before the price goes, so the payment keeps its quantity; it rounds down, so it never grows.
            let typed = AmountEntry(quantity, maximumFractionDigits: updated.decimals)
            unit = .token
            entry = typed ?? AmountEntry(maximumFractionDigits: updated.decimals)
        }
        token = updated
    }

    /// Pays with another token, keeping a currency amount when the new token has a price.
    /// - Parameter token: The token to pay with.
    private func select(_ token: PaymentToken) {
        guard token != self.token else { return }
        guard unit == .currency, token.price != nil else {
            restart(in: token)
            return
        }
        self.token = token
    }

    /// Selects a token with an empty amount, typed in tokens when the token has no price.
    /// - Parameter token: The token to pay with.
    private func restart(in token: PaymentToken) {
        self.token = token
        unit = token.price == nil ? .token : unit
        entry = emptyEntry
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

    /// An empty amount in the selected token and unit.
    private var emptyEntry: AmountEntry {
        AmountEntry(maximumFractionDigits: Self.fractionDigits(of: unit, token: token, currencyCode: currencyCode))
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
