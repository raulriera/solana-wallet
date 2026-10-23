import Accessibility
import SwiftUI

/// The typed amount over the line that converts it, shows the balance, or warns that it's more than the balance.
///
/// It reads the amount itself, so each key press updates only this summary.
struct AmountSummary: View {
    @Environment(\.locale) private var locale
    let payment: PaymentModel

    var body: some View {
        @Bindable var payment = payment
        let amount = payment.entry.formatted(.entry(in: payment.entryUnit).locale(locale))
        VStack(spacing: 12) {
            AmountDisplay(text: amount, rejectionCount: payment.rejectionCount)
            if payment.offersChoices {
                AmountUnitMenu(token: $payment.tokenChoice, unit: $payment.unitChoice, tokens: payment.tokens,
                               currencyCode: payment.currencyCode) {
                    AmountCaption(payment: payment)
                }
            } else {
                AmountCaption(payment: payment)
            }
        }
        .sensoryFeedback(.error, trigger: payment.rejectionCount)
        // VoiceOver hears the amount after each key, with the balance warning in the same announcement, so neither
        // cuts off the other.
        .onChange(of: payment.pressCount) {
            announce(payment.exceedsBalance ? String(localized: payment.source.overBalance(amount)) : amount)
        }
        // Another token or unit can clear or convert the amount; VoiceOver hears the new amount after the menu
        // closes.
        .onChange(of: payment.entryUnit) { announce(amount, isQueued: true) }
        // A rejected key or conversion leaves the amount as it was; VoiceOver hears why after the amount.
        .onChange(of: payment.rejectionCount) {
            if let rejection = payment.rejection { announce(String(localized: rejection.message), isQueued: true) }
        }
    }

    /// Reads a change aloud to VoiceOver.
    /// - Parameters:
    ///   - text: What to announce.
    ///   - isQueued: Whether the announcement waits for current speech instead of interrupting it.
    private func announce(_ text: String, isQueued: Bool = false) {
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = isQueued ? .low : .default
        AccessibilityNotification.Announcement(announcement).post()
    }
}
