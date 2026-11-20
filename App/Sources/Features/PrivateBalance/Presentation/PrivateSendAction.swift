/// Opens the choice of who to send a private balance to.
struct PrivateSendAction {
    let model: PrivateBalanceModel

    /// Opens the choice of recipient, unless a sheet is open.
    func callAsFunction() {
        model.openRecipients()
    }
}
