import SwiftUI

/// A form button row's title with a spinner at the trailing edge while the button's work runs.
struct PendingLabel: View {
    let title: LocalizedStringResource
    let isPending: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isPending {
                ProgressView()
            }
        }
    }
}

#Preview("Ready") {
    PendingLabel(title: "Send", isPending: false)
}

#Preview("Pending") {
    PendingLabel(title: "Send", isPending: true)
}
