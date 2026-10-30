import RPC
import SwiftUI

/// A network choice with a checkmark while it's selected.
struct NetworkRow: View {
    let name: LocalizedStringResource
    let network: Network
    @Binding var selection: Network

    var body: some View {
        Button(name) { selection = network }
            .buttonStyle(.choice(isSelected: selection == network))
    }
}
