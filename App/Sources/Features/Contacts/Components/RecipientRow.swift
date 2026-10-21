import SwiftUI
import Transactions

/// One address in the contacts list: its name over its short address, or, unsaved, its short address over when it
/// was last paid.
struct RecipientRow: View {
    /// The name the address is saved under, or `nil` when it isn't saved.
    let name: String?
    let address: Address
    /// When the address was last paid, shown under an unsaved address.
    let date: Date?
    /// The name of the SF Symbol that pictures the row's section.
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                if let name {
                    Text(name)
                    ShortAddress(address: address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ShortAddress(address: address)
                    if let date {
                        Text(date, format: .relative(presentation: .named))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        RecipientRow(name: "Alice", address: try! Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"), date: nil,
                     systemImage: "person.crop.circle")
        RecipientRow(name: nil, address: try! Address("44korouVTkSZ4u3SAT4BCg5S2AqJTV7osjVGVkjs3vtV"),
                     date: .now.addingTimeInterval(-3 * 24 * 60 * 60), systemImage: "clock")
    }
    .listStyle(.sidebar)
}
