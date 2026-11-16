import Foundation
import Observation
import Transactions

/// A model of a payment's typed amount, its token, and the unit it's typed in.
@MainActor
@Observable
final class PaymentModel {
    /// The unit that the keypad types in.
    nonisolated enum Unit: Hashable, Sendable {
        /// The person's currency, converted at the token's price.
        case currency
        case token
    }

    /// The balance of the account that the payment spends.
    nonisolated enum Source: Hashable, Sendable {
        /// The account's tokens, without naming a balance.
        case account
        case publicBalance
        /// The account's available private balance.
        case privateBalance

        /// Returns the named balance that the payment spends.
        ///
        /// - Parameters:
        ///   - balance: The balance.
        ///   - format: The style that formats the balance in its unit, such as 1.2 SOL or $172.64.
        /// - Returns: The balance with its name, such as "Public balance: 1.2 SOL".
        func balance<Style: FormatStyle & Sendable>(_ balance: Style.FormatInput,
                                                    format: Style) -> LocalizedStringResource
        where Style.FormatInput: Sendable, Style.FormatOutput == String {
            switch self {
            case .account:
                LocalizedStringResource("Balance: \(balance, format: format)",
                                        comment: "Line under a payment's amount. The variable is the balance in the unit of the amount, such as 1.2 SOL or $172.64.")
            case .publicBalance:
                LocalizedStringResource("Public balance: \(balance, format: format)",
                                        comment: "Line under the amount added to a private balance. The variable is the public balance in the unit of the amount, such as 1.2 SOL or $172.64.")
            case .privateBalance:
                LocalizedStringResource("Private balance: \(balance, format: format)",
                                        comment: "Line under the amount moved to the public balance. The variable is the available private balance in the unit of the amount, such as 1.2 SOL or $172.64.")
            }
        }

        /// The warning when the amount is more than the balance.
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

        /// Returns an amount with a warning that it's more than the balance.
        ///
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

    private(set) var tokens: [PaymentToken]
    /// The code of the person's currency.
    private(set) var currencyCode: String
    let source: Source
    private(set) var token: PaymentToken
    private(set) var unit: Unit
    private(set) var entry: AmountEntry
    /// The number of key presses, accepted or not.
    private(set) var pressCount = 0
    /// Why the last key or conversion was rejected, or `nil` after an accepted key.
    private(set) var rejection: AmountRejection?
    /// The number of rejected keys and conversions.
    private(set) var rejectionCount = 0

    /// Creates an empty amount in the first token, typed in the person's currency when the token has a price.
    ///
    /// - Parameters:
    ///   - tokens: The tokens the account can pay with, which can't be empty.
    ///   - currencyCode: The code of the person's currency.
    ///   - source: The balance that the payment spends.
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
        case .token: worth(of: entry.value)
        }
    }

    /// The typed amount of the token, or `nil` when it is zero, more than the balance, or too large for 64 bits.
    var sent: TokenAmount? {
        guard quantity > 0, !exceedsBalance else { return nil }
        return TokenAmount(quantity, decimals: token.balance.decimals)
    }

    var entryUnit: AmountEntryFormatStyle.Unit {
        switch unit {
        case .currency: .currency(code: currencyCode)
        case .token: .token(symbol: token.asset.displaySymbol)
        }
    }

    /// The token's balance in the unit that the amount is typed in, rounded down to the digits that unit allows.
    var entryBalance: Decimal {
        switch unit {
        case .token: Decimal(token.balance)
        case .currency: currencyBalance(digits: entry.maximumFractionDigits)
        }
    }

    /// The named balance in the unit that the amount is typed in, such as "Balance: $172.64".
    var balanceText: LocalizedStringResource {
        switch unit {
        case .currency: source.balance(entryBalance, format: .value(code: currencyCode))
        case .token: source.balance(token.balance, format: .amount(of: token.asset))
        }
    }

    var exceedsBalance: Bool { entry.value > entryBalance }

    /// Whether the amount is more than zero and no more than the balance.
    var canSend: Bool { sent != nil }

    /// Whether the person can pay with another token or type the amount in another unit.
    var offersChoices: Bool { tokens.count > 1 || token.price != nil }

    /// The token to pay with, which keeps a currency amount when set to another token with a price.
    var tokenChoice: PaymentToken {
        get { token }
        set { select(newValue) }
    }

    /// The unit to type in, which converts the typed amount when set.
    var unitChoice: Unit {
        get { unit }
        set { switchUnit(to: newValue) }
    }

    /// Applies a key press and counts it.
    ///
    /// - Parameter key: The pressed key.
    func press(_ key: KeypadKey) {
        if entry.press(key) {
            rejection = nil
        } else {
            reject(.key)
        }
        pressCount += 1
    }

    /// Clears the amount, keeping the token and the unit it's typed in.
    func clear() {
        entry = emptyEntry
        rejection = nil
    }

    /// Updates the tokens and currency, keeping the selected token and the typed amount when they remain.
    ///
    /// - Parameters:
    ///   - tokens: The tokens the account can pay with, which can't be empty.
    ///   - currencyCode: The code of the currency that their prices are in.
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
            restart(in: updated)
            return
        }
        guard updated != token else { return }
        if unit == .currency, updated.price == nil {
            let digits = Self.fractionDigits(of: .token, token: updated, currencyCode: currencyCode)
            let typed = AmountEntry(quantity, maximumFractionDigits: digits)
            unit = .token
            entry = typed ?? AmountEntry(maximumFractionDigits: digits)
        }
        token = updated
    }

    /// Pays with another token, keeping a currency amount when the new token has a price.
    ///
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
    ///
    /// - Parameter token: The token to pay with.
    private func restart(in token: PaymentToken) {
        self.token = token
        unit = token.price == nil ? .token : unit
        entry = emptyEntry
    }

    /// Converts the typed amount to another unit, or rejects a conversion too large to type.
    ///
    /// - Parameter unit: The unit to type in.
    private func switchUnit(to unit: Unit) {
        guard unit != self.unit, token.price != nil else { return }
        let digits = Self.fractionDigits(of: unit, token: token, currencyCode: currencyCode)
        let converted: AmountEntry?
        switch unit {
        case .token:
            converted = AmountEntry(quantity, maximumFractionDigits: digits)
        case .currency:
            let worth = value ?? 0
            let nearest = AmountEntry(worth, maximumFractionDigits: digits, rounding: .plain, padsFraction: true)
            let balance = currencyBalance(digits: digits)
            converted = nearest.flatMap { quantity(worth: $0.value) <= quantity && $0.value <= balance ? $0 : nil }
                ?? AmountEntry(worth, maximumFractionDigits: digits, padsFraction: true)
        }
        guard let converted else {
            reject(.conversion)
            return
        }
        self.unit = unit
        entry = converted
    }

    private var emptyEntry: AmountEntry {
        AmountEntry(maximumFractionDigits: Self.fractionDigits(of: unit, token: token, currencyCode: currencyCode))
    }

    /// Returns the token quantity that a value in the person's currency buys, rounded down to the token's decimals.
    ///
    /// - Parameter value: The value in the person's currency.
    /// - Returns: The quantity, or zero when the token has no price.
    private func quantity(worth value: Decimal) -> Decimal {
        guard let price = token.price, price > 0 else { return 0 }
        return (value / price).rounded(scale: Int(token.balance.decimals), .down)
    }

    /// Returns what a token quantity is worth in the person's currency.
    ///
    /// - Parameter quantity: The token quantity.
    /// - Returns: The value, or `nil` when the token has no price.
    private func worth(of quantity: Decimal) -> Decimal? {
        token.price.map { quantity * $0 }
    }

    /// Returns the token's balance in the person's currency, rounded down so that typing it never exceeds the balance.
    ///
    /// - Parameter digits: The currency's fraction digits.
    /// - Returns: The balance, or zero when the token has no price.
    private func currencyBalance(digits: Int) -> Decimal {
        (worth(of: Decimal(token.balance)) ?? 0).rounded(scale: digits, .down)
    }

    /// Records and counts a rejection.
    ///
    /// - Parameter rejection: The reason the amount didn't change.
    private func reject(_ rejection: AmountRejection) {
        self.rejection = rejection
        rejectionCount += 1
    }

    /// Returns how many fraction digits a unit allows.
    ///
    /// - Parameters:
    ///   - unit: The unit the keypad types in.
    ///   - token: The selected token.
    ///   - currencyCode: The code of the person's currency.
    /// - Returns: The token's decimals, or the currency's minor units, such as 2 for dollars or 0 for yen.
    private static func fractionDigits(of unit: Unit, token: PaymentToken, currencyCode: String) -> Int {
        switch unit {
        case .token:
            return Int(token.balance.decimals)
        case .currency:
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
            return formatter.maximumFractionDigits
        }
    }
}
