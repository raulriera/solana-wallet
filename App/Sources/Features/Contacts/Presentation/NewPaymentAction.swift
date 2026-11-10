import SwiftUI
import Transactions

/// An action that leaves the selected recipient so the person can choose who to pay next.
struct NewPaymentAction {
    let selection: Binding<Address?>

    /// Clears the selected recipient.
    func callAsFunction() {
        selection.wrappedValue = nil
    }
}
