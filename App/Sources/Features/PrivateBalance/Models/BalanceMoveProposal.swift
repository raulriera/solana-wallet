import Foundation
import Privacy
import RPC
import Transactions

/// A proposed move of the account's asset between its public and private balances.
struct BalanceMoveProposal: TransactionProposal {
    /// The balance that the asset leaves and the one that it reaches.
    nonisolated enum Direction: Hashable, Sendable {
        case toPrivate
        case toPublic

        /// Returns the title of a move of a token in this direction.
        ///
        /// - Parameter symbol: The token's symbol, such as SOL.
        /// - Returns: The title, such as Make SOL Private.
        func title(of symbol: String) -> LocalizedStringResource {
            switch self {
            case .toPrivate:
                LocalizedStringResource(
                    "Make \(symbol) Private",
                    comment: "Title of moving a token into the private balance. The variable is the token's symbol, such as SOL or USDC."
                )
            case .toPublic:
                LocalizedStringResource(
                    "Make \(symbol) Public",
                    comment: "Title of moving a token out of the private balance. The variable is the token's symbol, such as SOL or USDC."
                )
            }
        }
    }

    /// The move's costs and pending change.
    nonisolated struct Review: Equatable, Sendable {
        /// The network fee with any service tip, in lamports.
        let networkFee: UInt64
        /// The fee of the account's first registration, in lamports, or `nil` when it's registered.
        let registrationFee: UInt64?
        /// The pool's fee for the trees that the spend writes, in lamports, or `nil` when there's none.
        let privacyFee: UInt64?
        /// The change returned to the private balance, in the asset's smallest unit, or `nil` when there's none.
        let pendingChange: UInt64?
    }

    typealias Error = PrivateBalanceError

    let direction: Direction
    let asset: PrivateAsset
    let amount: PaymentAmount
    let balances: any PrivateBalancing

    /// The move's title, such as Make USDC Private.
    var title: LocalizedStringResource { direction.title(of: amount.token.symbol) }

    var refreshInterval: Duration { .seconds(30) }

    func prepare(from account: Account, on network: Network) async throws -> PreparedPrivateTransaction {
        let request: PrivateTransactionRequest =
            switch direction {
            case .toPrivate: .deposit(amount.units, of: asset)
            case .toPublic: .withdraw(amount.units, of: asset, to: account.address)
            }
        return try await balances.prepare(request, from: account, on: network)
    }

    func simulate(_ preparation: PreparedPrivateTransaction, with coordinator: any TransactionCoordinating,
                  from account: Account) async throws -> ProposedTransaction<Review> {
        let (simulation, transaction) = try await coordinator.simulate(preparation)
        let execution = simulation.diagnostics.value
        guard execution.error == nil else {
            guard execution.lacksFunds else { throw PrivateBalanceError.preparationFailed }
            throw switch direction {
            case .toPrivate where asset == .sol: PrivateBalanceError.insufficientPublicBalance
            case .toPrivate, .toPublic: PrivateBalanceError.insufficientPublicBalanceForFees
            }
        }
        guard let networkFee = simulation.networkFee else { throw PrivateBalanceError.preparationFailed }
        let movedLamports = asset.lamports(moving: amount.units)
        let review: Review
        let kind: TransactionRecord.Kind
        switch preparation.effect {
        case .deposit:
            let registrationFee = preparation.registers
                ? try otherFee(of: simulation, for: account, paying: movedLamports, networkFee: networkFee) : nil
            review = Review(networkFee: networkFee, registrationFee: registrationFee, privacyFee: nil,
                            pendingChange: nil)
            kind = .privateDeposit
        case .spend(let spend):
            let privacyFee = try otherFee(
                of: simulation,
                for: account,
                receiving: movedLamports,
                networkFee: networkFee
            )
            review = Review(
                networkFee: networkFee,
                registrationFee: nil,
                privacyFee: privacyFee > 0 ? privacyFee : nil,
                pendingChange: spend.receivedAmount > 0 ? spend.receivedAmount : nil
            )
            kind = .privateWithdrawal
        case .createCode, .redeem:
            throw PrivateBalanceError.preparationFailed
        }
        return ProposedTransaction(simulation: simulation, review: review, kind: kind,
                                   settling: PrivateBalanceSettlement(balances: balances, transaction: transaction))
    }

    /// Returns what the account's public SOL pays in a simulation beyond the moved SOL and the network fee.
    ///
    /// - Parameters:
    ///   - simulation: The simulated move.
    ///   - account: The account whose public SOL pays.
    ///   - paid: The SOL that the public balance pays into the private balance, in lamports.
    ///   - received: The SOL that the public balance receives from the private balance, in lamports.
    ///   - networkFee: The network fee and the service tip, in lamports.
    /// - Returns: The other fees, in lamports.
    /// - Throws: ``PrivateBalanceError/preparationFailed`` if the simulation doesn't report the account's SOL or
    ///   reports too little.
    private func otherFee(of simulation: Simulation, for account: Account, paying paid: UInt64 = 0,
                          receiving received: UInt64 = 0, networkFee: UInt64) throws -> UInt64 {
        guard let change = simulation.balanceChanges?.first(where: { $0.owner == account.address && $0.asset == .sol })
        else { throw PrivateBalanceError.preparationFailed }
        let (incoming, incomingOverflow) = change.before.addingReportingOverflow(received)
        let (kept, keptOverflow) = change.after.addingReportingOverflow(paid)
        let (outgoing, outgoingOverflow) = kept.addingReportingOverflow(networkFee)
        guard !incomingOverflow, !keptOverflow, !outgoingOverflow, incoming >= outgoing else {
            throw PrivateBalanceError.preparationFailed
        }
        return incoming - outgoing
    }
}
