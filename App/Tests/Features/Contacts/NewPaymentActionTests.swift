import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NewPaymentActionTests {
    @Test func `Starting a new payment clears the selected recipient`() {
        let selection = BindingSource<Address?>(ContactsFixtures.alice)
        let action = NewPaymentAction(selection: selection.binding)

        action()

        #expect(selection.value == nil)
    }
}
