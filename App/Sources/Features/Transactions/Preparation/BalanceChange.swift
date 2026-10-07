import RPC
import Transactions

/// A balance difference observed in simulation for one owner and asset.
///
/// Changes describe simulated execution only. They don't establish program intent,
/// user consent, scam safety, or future execution.
nonisolated struct BalanceChange: Sendable, Equatable {
    /// The asset whose balance changed.
    enum Asset: Sendable, Hashable {
        /// Native SOL held by the owner's own account, in lamports.
        case sol
        /// One mint's raw units across the owner's token accounts.
        case token(mint: Address, decimals: UInt8)
    }

    /// The account holding SOL, or the owner of the token accounts.
    let owner: Address
    /// The changed asset.
    let asset: Asset
    /// The balance before execution, in lamports or raw token units.
    let before: UInt64
    /// The balance after execution, in lamports or raw token units.
    let after: UInt64

    /// Compares the node's balances before and after execution.
    ///
    /// SOL changes use each account's own lamports, so deposits into token accounts
    /// aren't attributed to their owners. Token changes sum raw units per owner and mint.
    ///
    /// - Parameters:
    ///   - transaction: The simulated transaction whose account list indexes the balances.
    ///   - simulation: The execution outcome with balances before and after.
    /// - Returns: The changed balances, SOL in account order and then tokens in observation
    ///   order, or `nil` if balances are missing or can't be attributed to the transaction.
    static func changes(in transaction: Transaction, from simulation: SimulateTransaction.Value) -> [BalanceChange]? {
        guard let lamportsBefore = simulation.preBalances, let lamportsAfter = simulation.postBalances,
              let tokensBefore = simulation.preTokenBalances, let tokensAfter = simulation.postTokenBalances,
              lamportsBefore.count == transaction.accounts.count, lamportsAfter.count == transaction.accounts.count else {
            return nil
        }
        var changes = zip(transaction.accounts, zip(lamportsBefore, lamportsAfter)).compactMap { account, lamports in
            lamports.0 == lamports.1 ? nil : BalanceChange(owner: account.address, asset: .sol, before: lamports.0, after: lamports.1)
        }
        var holdings: [Holding] = []
        var totals: [Holding: Totals] = [:]
        for (balances, phase) in [(tokensBefore, \Totals.before), (tokensAfter, \Totals.after)] {
            for balance in balances {
                guard transaction.accounts.indices.contains(balance.accountIndex), let recordedOwner = balance.owner,
                      let owner = try? Address(recordedOwner), let mint = try? Address(balance.mint) else { return nil }
                let holding = Holding(owner: owner, asset: .token(mint: mint, decimals: balance.decimals))
                var total = totals[holding] ?? Totals()
                let (sum, overflow) = total[keyPath: phase].addingReportingOverflow(balance.amount)
                guard !overflow else { return nil }
                total[keyPath: phase] = sum
                if totals.updateValue(total, forKey: holding) == nil { holdings.append(holding) }
            }
        }
        for holding in holdings {
            guard let total = totals[holding], total.before != total.after else { continue }
            changes.append(BalanceChange(owner: holding.owner, asset: holding.asset, before: total.before, after: total.after))
        }
        return changes
    }

    /// One owner's position in one asset.
    private struct Holding: Hashable {
        let owner: Address
        let asset: Asset
    }

    /// Raw units summed across one holding's token accounts.
    private struct Totals {
        var before: UInt64 = 0
        var after: UInt64 = 0
    }
}
