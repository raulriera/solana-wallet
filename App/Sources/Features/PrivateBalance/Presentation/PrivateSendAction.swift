/// Opens the choice of who to send a private balance to.
struct PrivateSendAction {
    let model: PrivateBalanceModel

    /// Opens the choice of recipient, unless a move is open.
    func callAsFunction() {
        model.openSend()
    }
}
