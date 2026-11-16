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
        /// The rent that opens the account's token account for a withdrawal, in lamports, or `nil` when it has one.
        let accountDeposit: UInt64?
    }

    typealias Error = PrivateBalanceError

    let direction: Direction
    let asset: Asset
    /// The amount of the asset that moves.
    let sent: TokenAmount
    let balances: any PrivateBalancing

    /// The move's title, such as Make USDC Private.
    var title: LocalizedStringResource { direction.title(of: asset.displaySymbol) }

    var refreshInterval: Duration { .seconds(30) }

    func prepare(from account: Account, on network: Network) async throws -> PreparedPrivateTransaction {
        guard let privateAsset = PrivateAsset(asset.id) else { throw PrivateBalanceError.preparationFailed }
        let request: PrivateTransactionRequest =
            switch direction {
            case .toPrivate: .deposit(sent.amount, of: privateAsset)
            case .toPublic: .withdraw(sent.amount, of: privateAsset, to: account.address)
            }
        return try await balances.prepare(request, from: account, on: network)
    }

    func simulate(_ preparation: PreparedPrivateTransaction, with coordinator: any TransactionCoordinating,
                  from account: Account) async throws -> ProposedTransaction<Review> {
        guard let privateAsset = PrivateAsset(asset.id) else { throw PrivateBalanceError.preparationFailed }
        let (simulation, transaction) = try await coordinator.simulate(preparation)
        let execution = simulation.diagnostics.value
        guard execution.error == nil else {
            guard execution.lacksFunds else { throw PrivateBalanceError.preparationFailed }
            throw switch direction {
            case .toPrivate where privateAsset == .nativeSOL: PrivateBalanceError.insufficientPublicBalance
            case .toPrivate, .toPublic: PrivateBalanceError.insufficientPublicBalanceForFees
            }
        }
        guard let networkFee = simulation.networkFee else { throw PrivateBalanceError.preparationFailed }
        let movedLamports = privateAsset.lamports(moving: sent.amount)
        let review: Review
        let kind: TransactionRecord.Kind
        switch preparation.effect {
        case .deposit:
            let registrationFee = preparation.registers
                ? try otherFee(of: simulation, for: account, paying: movedLamports, networkFee: networkFee) : nil
            review = Review(networkFee: networkFee, registrationFee: registrationFee, privacyFee: nil,
                            pendingChange: nil, accountDeposit: nil)
            kind = .privateDeposit
        case .spend(let spend):
            let accountDeposit = try privateAsset.tokenAccount(of: account.address).flatMap {
                openingDeposit(of: $0, in: simulation)
            }
            let privacyFee = try otherFee(
                of: simulation,
                for: account,
                paying: accountDeposit ?? 0,
                receiving: movedLamports,
                networkFee: networkFee
            )
            review = Review(
                networkFee: networkFee,
                registrationFee: nil,
                privacyFee: privacyFee.nonZero,
                pendingChange: spend.receivedAmount.nonZero,
                accountDeposit: accountDeposit
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
    ///   - paid: The SOL that the public balance pays beyond the fees, such as into the private balance or a new token
    ///     account, in lamports.
    ///   - received: The SOL that the public balance receives from the private balance, in lamports.
    ///   - networkFee: The network fee and the service tip, in lamports.
    /// - Returns: The other fees, in lamports.
    /// - Throws: ``PrivateBalanceError/preparationFailed`` if the simulation doesn't report the account's SOL or
    ///   reports too little.
    private func otherFee(of simulation: Simulation, for account: Account, paying paid: UInt64 = 0,
                          receiving received: UInt64 = 0, networkFee: UInt64) throws -> UInt64 {
        guard let change = solChange(of: account.address, in: simulation) else { throw PrivateBalanceError.preparationFailed }
        let (incoming, incomingOverflow) = change.before.addingReportingOverflow(received)
        let (kept, keptOverflow) = change.after.addingReportingOverflow(paid)
        let (outgoing, outgoingOverflow) = kept.addingReportingOverflow(networkFee)
        guard !incomingOverflow, !keptOverflow, !outgoingOverflow, incoming >= outgoing else {
            throw PrivateBalanceError.preparationFailed
        }
        return incoming - outgoing
    }

    /// Returns the rent that a simulation pays into a token account that it opens.
    ///
    /// - Parameters:
    ///   - tokenAccount: The token account.
    ///   - simulation: The simulated move.
    /// - Returns: The account's rent in lamports, or `nil` when the simulation doesn't open it.
    private func openingDeposit(of tokenAccount: Address, in simulation: Simulation) -> UInt64? {
        guard let change = solChange(of: tokenAccount, in: simulation), change.before == 0 else { return nil }
        return change.after
    }

    /// Returns the change that a simulation shows in an account's SOL.
    ///
    /// - Parameters:
    ///   - address: The account.
    ///   - simulation: The simulated move.
    /// - Returns: The change, or `nil` when the simulation doesn't change or report it.
    private func solChange(of address: Address, in simulation: Simulation) -> BalanceChange? {
        simulation.balanceChanges?.first { $0.owner == address && $0.asset == .nativeSOL }
    }
}
