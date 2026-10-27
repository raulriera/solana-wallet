import Foundation
import Privacy
import RPC
import Transactions

/// A move of an amount of the account's SOL between its public balance and its own private balance, as its review
/// shows it.
///
/// Each review proves the move once, and each simulation reuses that proof. The account's public SOL pays every fee: a
/// deposit's network fee and first registration, and a withdrawal's network fee and privacy fee.
struct BalanceMoveProposal: TransactionProposal {
    /// Which balance the SOL leaves, and which one it reaches.
    nonisolated enum Direction: Hashable, Sendable {
        /// From the account's public balance into its private balance.
        case toPrivate
        /// From the account's available private balance to its own public address.
        case toPublic

        /// The task's name, which titles its keypad, its result, and its approval.
        var title: LocalizedStringResource {
            switch self {
            case .toPrivate: "Make SOL Private"
            case .toPublic: "Make SOL Public"
            }
        }
    }

    /// What the person approves beyond the amount: what the move costs, and what it returns to the private balance.
    nonisolated struct Review: Equatable, Sendable {
        /// The network fee, with any service tip, in lamports.
        let networkFee: UInt64
        /// The one-time fee that registers the account with its first move into the private balance, in lamports, or
        /// `nil` after it.
        let registrationFee: UInt64?
        /// The pool's fee for the notes that a move to the public balance spends, in lamports, or `nil` when there's
        /// none.
        let privacyFee: UInt64?
        /// The change that a move to the public balance returns to the private balance, pending until the network
        /// reports it, in lamports, or `nil` when there's none.
        let pendingChange: UInt64?
    }

    /// The errors that the move's alerts explain.
    typealias Error = PrivateBalanceError

    /// Which balance the SOL leaves, and which one it reaches.
    let direction: Direction
    /// The amount as typed when the person tapped Review, in SOL from the balance that it leaves.
    let amount: PaymentAmount
    /// The private balances of every account, which prepare the move and record its outcome.
    let balances: any PrivateBalancing

    /// A review expires after about a minute, so it's simulated again well before it does.
    var refreshInterval: Duration { .seconds(30) }

    /// Syncs the account's notes and proves the move.
    /// - Parameters:
    ///   - account: The account whose SOL moves; it signs and pays.
    ///   - network: The network that the move runs on.
    /// - Returns: The proved move, which every simulation of this review uses.
    /// - Throws: A ``PrivateBalanceError`` from the private balances, or a storage, provider, or proof error.
    func prepare(from account: Account, on network: Network) async throws -> PreparedPrivateTransaction {
        let request: PrivateTransactionRequest = switch direction {
        case .toPrivate: .deposit(amount.units)
        case .toPublic: .withdraw(amount.units, to: account.address)
        }
        return try await balances.prepare(request, from: account, on: network)
    }

    /// Simulates the proved move and reads what it costs.
    /// - Parameters:
    ///   - preparation: The proved deposit or withdrawal.
    ///   - coordinator: The network's transaction coordinator, which simulates the move.
    ///   - account: The account whose public SOL pays the fees.
    /// - Returns: The simulation to approve, what it costs, the move's record kind, and the settling that records its
    ///   outcome in the private balance.
    /// - Throws: ``PrivateBalanceError/insufficientPublicBalance`` if the public SOL doesn't cover a deposit and its
    ///   fees, ``PrivateBalanceError/insufficientPublicBalanceForFees`` if it doesn't cover a withdrawal's fees,
    ///   ``PrivateBalanceError/preparationFailed`` if the simulation fails otherwise or doesn't report the fees, or the
    ///   simulation's error.
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
            // Only a first deposit pays more: the registration's rent.
            let registrationFee = preparation.registers
                ? try otherFee(of: simulation, for: account, paying: lamports, networkFee: networkFee) : nil
            review = Review(networkFee: networkFee, registrationFee: registrationFee, privacyFee: nil,
                            pendingChange: nil)
            kind = .privateDeposit(lamports: lamports)
        case .spend(let spend):
            let privacyFee = try otherFee(of: simulation, for: account, receiving: spend.lamports,
                                          networkFee: networkFee)
            // The spent notes' change returns to the private balance.
            review = Review(networkFee: networkFee, registrationFee: nil, privacyFee: privacyFee > 0 ? privacyFee : nil,
                            pendingChange: spend.receivedLamports > 0 ? spend.receivedLamports : nil)
            kind = .privateWithdrawal(lamports: spend.lamports)
        case .createCode, .redeem:
            // Moves between the account's own balances never create or redeem codes.
            throw PrivateBalanceError.preparationFailed
        }
        return ProposedTransaction(simulation: simulation, review: review, kind: kind,
                                   settling: PrivateBalanceSettlement(balances: balances, transaction: transaction))
    }

    /// Reads what the account's public SOL pays in a simulation beyond the SOL that moves and the network fee, such as
    /// a registration's rent or a withdrawal's privacy fee.
    /// - Parameters:
    ///   - simulation: The simulated move.
    ///   - account: The account whose public SOL pays.
    ///   - paid: The SOL that the public balance pays into the private balance, in lamports.
    ///   - received: The SOL that the public balance receives from the private balance, in lamports.
    ///   - networkFee: The network fee and service tips, in lamports.
    /// - Returns: The other fees, in lamports.
    /// - Throws: ``PrivateBalanceError/preparationFailed`` if the simulation doesn't report the account's SOL, or
    ///   reports less than the SOL that moves and the network fee.
    private func otherFee(of simulation: Simulation, for account: Account, paying paid: UInt64 = 0,
                          receiving received: UInt64 = 0, networkFee: UInt64) throws -> UInt64 {
        guard let change = simulation.balanceChanges?.first(where: { $0.owner == account.address && $0.asset == .sol })
        else { throw PrivateBalanceError.preparationFailed }
        // What the account had and received equals what it keeps and pays.
        let (incoming, incomingOverflow) = change.before.addingReportingOverflow(received)
        let (kept, keptOverflow) = change.after.addingReportingOverflow(paid)
        let (outgoing, outgoingOverflow) = kept.addingReportingOverflow(networkFee)
        guard !incomingOverflow, !keptOverflow, !outgoingOverflow, incoming >= outgoing else {
            throw PrivateBalanceError.preparationFailed
        }
        return incoming - outgoing
    }
}
