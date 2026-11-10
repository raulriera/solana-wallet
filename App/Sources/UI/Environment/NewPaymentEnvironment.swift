import SwiftUI

extension EnvironmentValues {
    /// The action that leaves a sent payment to choose who to pay next, or `nil` outside Contacts.
    @Entry var newPayment: NewPaymentAction?
}
