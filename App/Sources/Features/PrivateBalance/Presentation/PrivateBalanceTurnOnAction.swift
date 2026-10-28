/// Turns private balances on from the private balance's Turn On row, the way SwiftUI's `dismiss` acts for the view
/// that reads it.
struct PrivateBalanceTurnOnAction {
    /// The Portfolio tab's private-balance workflows, which run the attempt with
    /// ``TokenDetailScreen/privateBalanceLifecycle()``.
    let model: PrivateBalanceModel

    /// Asks to turn private balances on, unless an attempt is already waiting or running.
    func callAsFunction() {
        model.turnOn()
    }
}
