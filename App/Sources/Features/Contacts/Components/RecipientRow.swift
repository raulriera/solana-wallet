import SwiftUI
import Transactions

/// A row that shows an address with its name, or with when it was last paid.
struct RecipientRow: View {
    /// The name the address is saved under, or `nil` when it isn't saved.
    let name: String?
    let address: Address
    /// When the address was last paid.
    let date: Date?
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
            .foregroundStyle(.selectionAware(.primary))
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.selectionAware(.tint))
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    if let alice = try? Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
       let recent = try? Address("44korouVTkSZ4u3SAT4BCg5S2AqJTV7osjVGVkjs3vtV") {
        List {
            RecipientRow(name: "Alice", address: alice, date: nil,
                         systemImage: "person.crop.circle")
            RecipientRow(name: nil, address: recent,
                         date: .now.addingTimeInterval(-3 * 24 * 60 * 60), systemImage: "clock")
        }
        .listStyle(.sidebar)
    }
}
