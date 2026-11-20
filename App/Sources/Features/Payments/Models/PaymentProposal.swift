import Foundation
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
        /// The fee that the token's mint withholds from what the recipient receives, or `nil` when it takes none.
        let transferFee: TokenAmount?
    }

    typealias Error = SendError

    let asset: Asset
    /// The amount of the asset that the payment sends.
    let sent: TokenAmount
    /// What the sent amount is worth in ``currencyCode``, or `nil` when the asset has no price.
    let value: Decimal?
    /// The code of the person's currency.
    let currencyCode: String
    let recipient: PaymentRecipient
    /// The recipient warnings, most serious first.
    let warnings: [RecipientWarning]
    /// The store that keeps the recipient once the payment succeeds.
    let recents: RecentPaymentStore

    var refreshInterval: Duration { .seconds(10) }

    func simulate(_ preparation: Void, with coordinator: any TransactionCoordinating, from account: Account)
        async throws -> ProposedTransaction<Review> {
        let simulation = try await coordinator.transfer(sent.amount, of: asset, using: account, to: recipient.address)
        let execution = simulation.diagnostics.value
        guard execution.error == nil else {
            if execution.lacksFunds { throw SendError.notEnoughSOL }
            if execution.opensAccountBelowRent { throw SendError.amountTooSmall }
            throw SendError.preparationFailed
        }
        guard let networkFee = simulation.networkFee else { throw SendError.preparationFailed }
        let accountDeposit = simulation.destinationAccountRent?.nonZero
        let transferFee = simulation.tokenTransfer.flatMap { transfer in
            transfer.expectedFee?.nonZero.map { TokenAmount(amount: $0, decimals: transfer.mint.decimals) }
        }
        return ProposedTransaction(
            simulation: simulation,
            review: Review(networkFee: networkFee, accountDeposit: accountDeposit, transferFee: transferFee),
            kind: .payment,
            settling: RecentPaymentSettlement(recents: recents, recipient: recipient.address))
    }
}
