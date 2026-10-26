import RPC
import Transactions

/// A payment of an amount of one token from the window's account to a recipient, as its review shows it.
struct PaymentProposal: TransactionProposal {
    /// What the person approves beyond the amount: what the payment costs.
    nonisolated struct Review: Equatable, Sendable {
        /// The network fee, with any service tip, in lamports.
        let networkFee: UInt64
        /// The rent that opens the recipient's account for the token, in lamports, or `nil` when it has one.
        let accountDeposit: UInt64?
    }

    /// The errors that the payment's alerts explain.
    typealias Error = SendError

    /// The amount as typed when the person tapped Send.
    let amount: PaymentAmount
    /// Who the payment goes to.
    let recipient: PaymentRecipient
    /// What to check about the recipient, most serious first.
    let warnings: [RecipientWarning]

    /// A blockhash lasts about 30 seconds, so the review is simulated again well before it expires.
    var refreshInterval: Duration { .seconds(10) }

    /// Simulates the payment and reads what it costs.
    /// - Parameters:
    ///   - preparation: Nothing; each simulation builds the whole payment.
    ///   - coordinator: The network's transaction coordinator, which simulates the payment.
    ///   - account: The account that pays the amount and the fees.
    /// - Returns: The simulation to approve, what it costs, and the payment's record kind.
    /// - Throws: ``SendError/notEnoughSOL`` if the account's SOL doesn't cover the payment and its fees,
    ///   ``SendError/preparationFailed`` if the simulation fails otherwise or doesn't report the fee, or the
    ///   simulation's error.
    func simulate(_ preparation: Void, with coordinator: any TransactionCoordinating, from account: Account)
        async throws -> ProposedTransaction<Review> {
        let simulation = try await coordinator.transfer(amount.units, token: amount.token.mint, using: account,
                                                         to: recipient.address)
        let execution = simulation.diagnostics.value
        guard execution.error == nil else {
            throw execution.lacksFunds ? SendError.notEnoughSOL : SendError.preparationFailed
        }
        guard let networkFee = simulation.networkFee else { throw SendError.preparationFailed }
        let accountDeposit = simulation.destinationAccountRent.flatMap { $0 > 0 ? $0 : nil }
        return ProposedTransaction(
            simulation: simulation, review: Review(networkFee: networkFee, accountDeposit: accountDeposit),
            kind: .payment(recipient: recipient.address, mint: amount.token.mint, units: amount.units))
    }
}
