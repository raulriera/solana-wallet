import SwiftUI
import Transactions

/// A row that shows a recipient in a monogram circle, with its name, its address, and when it was last paid.
struct RecipientRow: View {
    let recipient: PaymentRecipient
    /// When the address was last paid, or `nil` when it never was.
    var date: Date?

    var body: some View {
        LabeledContent {
            if let date {
                Text(date, format: Date.RelativeFormatStyle(presentation: .named,
                                                             capitalizationContext: .beginningOfSentence))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .foregroundStyle(.selectionAware(.primary))
            }
        } label: {
            Label {
                if let name = recipient.name {
                    Text(name, format: .emphasizedGivenName)
                }
                ShortAddress(address: recipient.address)
            } icon: {
                Text(recipient, format: .monogram)
                    .fontWeight(.semibold)
                    .monogramIcon()
            }
            .labelStyle(.subtitled)
            .foregroundStyle(.selectionAware(.primary))
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    if let alice = try? Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
       let recent = try? Address("44korouVTkSZ4u3SAT4BCg5S2AqJTV7osjVGVkjs3vtV"),
       let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now),
       let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: .now) {
        List {
            RecipientRow(recipient: PaymentRecipient(address: alice, name: "Alice Smith"), date: yesterday)
            RecipientRow(recipient: PaymentRecipient(address: recent, name: nil), date: threeDaysAgo)
        }
        .listStyle(.sidebar)
    }
}
