import Testing
@testable import widgets

/// Checks that the private balance's turn-on action asks the tab's workflows to turn private balances on.
@MainActor
struct PrivateBalanceTurnOnActionTests {
    /// Turning on starts an attempt that the scene's task runs.
    @Test func `Turning on starts an attempt`() {
        let model = PrivateBalanceModel()
        let turnOn = PrivateBalanceTurnOnAction(model: model)

        turnOn()

        #expect(model.isTurningOn)
    }
}
