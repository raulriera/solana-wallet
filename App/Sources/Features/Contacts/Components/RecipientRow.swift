import SwiftUI
import Transactions

/// A row that shows an address in a monogram circle, with the name it's saved under and when it was last paid.
struct RecipientRow: View {
    /// The name the address is saved under, or `nil` when it isn't saved.
    let name: String?
    let address: Address
    /// When the address was last paid, or `nil` when it never was.
    var date: Date?

    var body: some View {
        LabeledContent {
            if let date {
                Text(date, format: Date.RelativeFormatStyle(presentation: .named,
                                                             capitalizationContext: .beginningOfSentence))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label {
                if let name {
                    Text(name, format: .emphasizedGivenName)
                    ShortAddress(address: address)
                } else {
                    ShortAddress(address: address)
                }
            } icon: {
                Text(PaymentRecipient(address: address, name: name), format: .monogram)
                    .font(.headline)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .circularIcon(.gray.gradient)
            }
            .labelStyle(.subtitled)
        }
        .foregroundStyle(.selectionAware(.primary))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    if let alice = try? Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
       let recent = try? Address("44korouVTkSZ4u3SAT4BCg5S2AqJTV7osjVGVkjs3vtV") {
        List {
            RecipientRow(name: "Alice Smith", address: alice, date: .now.addingTimeInterval(-24 * 60 * 60))
            RecipientRow(name: nil, address: recent, date: .now.addingTimeInterval(-3 * 24 * 60 * 60))
        }
        .listStyle(.plain)
    }
}
