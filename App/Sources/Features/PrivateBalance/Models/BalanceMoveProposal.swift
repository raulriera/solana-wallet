import Foundation
import Privacy
import RPC
import Transactions

/// A proposed move of the account's SOL between its public and private balances.
struct BalanceMoveProposal: TransactionProposal {
    /// The balance that the SOL leaves and the one that it reaches.
    nonisolated enum Direction: Hashable, Sendable {
        case toPrivate
        case toPublic

        var title: LocalizedStringResource {
            switch self {
            case .toPrivate: "Make SOL Private"
            case .toPublic: "Make SOL Public"
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
        /// The change returned to the private balance, in lamports, or `nil` when there's none.
        let pendingChange: UInt64?
    }

    typealias Error = PrivateBalanceError

    let direction: Direction
    let amount: PaymentAmount
    let balances: any PrivateBalancing

    var refreshInterval: Duration { .seconds(30) }

    func prepare(from account: Account, on network: Network) async throws -> PreparedPrivateTransaction {
        let request: PrivateTransactionRequest = switch direction {
        case .toPrivate: .deposit(amount.units)
        case .toPublic: .withdraw(amount.units, to: account.address)
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
            case .toPrivate: PrivateBalanceError.insufficientPublicBalance
            case .toPublic: PrivateBalanceError.insufficientPublicBalanceForFees
            }
        }
        guard let networkFee = simulation.networkFee else { throw PrivateBalanceError.preparationFailed }
        let review: Review
        let kind: TransactionRecord.Kind
        switch preparation.effect {
        case .deposit(let lamports):
            let registrationFee = preparation.registers
                ? try otherFee(of: simulation, for: account, paying: lamports, networkFee: networkFee) : nil
            review = Review(networkFee: networkFee, registrationFee: registrationFee, privacyFee: nil,
                            pendingChange: nil)
            kind = .privateDeposit(lamports: lamports)
        case .spend(let spend):
            let privacyFee = try otherFee(of: simulation, for: account, receiving: spend.lamports,
                                          networkFee: networkFee)
            review = Review(networkFee: networkFee, registrationFee: nil, privacyFee: privacyFee > 0 ? privacyFee : nil,
                            pendingChange: spend.receivedLamports > 0 ? spend.receivedLamports : nil)
            kind = .privateWithdrawal(lamports: spend.lamports)
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
