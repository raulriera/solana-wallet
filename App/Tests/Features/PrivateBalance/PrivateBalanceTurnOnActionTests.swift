import Testing
@testable import widgets

@MainActor
struct PrivateBalanceTurnOnActionTests {
    @Test func `Turning on starts an attempt`() {
        let model = PrivateBalanceModel()
        let turnOn = PrivateBalanceTurnOnAction(model: model)

        turnOn()

        #expect(model.isTurningOn)
    }
}
