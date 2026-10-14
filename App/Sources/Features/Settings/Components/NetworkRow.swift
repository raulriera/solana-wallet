import RPC
import SwiftUI

/// One network choice, with a checkmark while the owning window shows that network.
struct NetworkRow: View {
    let name: LocalizedStringResource
    let network: Network
    @Binding var selection: Network

    var body: some View {
        Button(name) { selection = network }
            .buttonStyle(.choice(isSelected: selection == network))
    }
}
