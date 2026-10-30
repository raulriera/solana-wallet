/// Asks to turn private balances on.
struct PrivateBalanceTurnOnAction {
    let model: PrivateBalanceModel

    /// Asks to turn private balances on, unless an attempt is already waiting or running.
    func callAsFunction() {
        model.turnOn()
    }
}
