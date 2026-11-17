import RPC
import Transactions

/// A payment of one token from an account to a recipient.
struct PaymentProposal: TransactionProposal {
    /// The costs of a payment that the person approves.
    nonisolated struct Review: Equatable, Sendable {
        /// The network fee, with any service tip, in lamports.
        let networkFee: UInt64
        /// The rent that opens the recipient's account for the token, in lamports, or `nil` when it has one.
        let accountDeposit: UInt64?
    }

    typealias Error = SendError

    let amount: PaymentAmount
    let recipient: PaymentRecipient
    /// The recipient warnings, most serious first.
    let warnings: [RecipientWarning]

    var refreshInterval: Duration { .seconds(10) }

    func simulate(_ preparation: Void, with coordinator: any TransactionCoordinating, from account: Account)
        async throws -> ProposedTransaction<Review> {
        let simulation = try await coordinator.transfer(amount.units, token: amount.token.mint, using: account,
                                                         to: recipient.address)
        let execution = simulation.diagnostics.value
        guard execution.error == nil else {
            if execution.lacksFunds { throw SendError.notEnoughSOL }
            if execution.opensAccountBelowRent { throw SendError.amountTooSmall }
            throw SendError.preparationFailed
        }
        guard let networkFee = simulation.networkFee else { throw SendError.preparationFailed }
        let accountDeposit = simulation.destinationAccountRent.flatMap { $0 > 0 ? $0 : nil }
        return ProposedTransaction(
            simulation: simulation, review: Review(networkFee: networkFee, accountDeposit: accountDeposit),
            kind: .payment(recipient: recipient.address, mint: amount.token.mint, units: amount.units))
    }
}
