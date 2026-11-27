public import Transactions

/// A balance change that a simulation shows for one owner and asset.
public struct BalanceChange: Sendable, Equatable {
    /// The account that holds the SOL, or the owner of the token accounts.
    public let owner: Address
    /// SOL in the owner's own account, or one mint's tokens across the owner's token accounts.
    public let asset: Asset.ID
    /// The balance before execution, in lamports or raw token units.
    public let before: UInt64
    /// The balance after execution, in lamports or raw token units.
    public let after: UInt64

    /// Returns the balances that a simulation changed.
    ///
    /// - Parameters:
    ///   - transaction: The simulated transaction, whose accounts index the balances.
    ///   - simulation: The simulation with balances before and after execution.
    /// - Returns: The changed balances, SOL first in account order, or `nil` if balances are missing or invalid.
    public static func changes(in transaction: Transaction, from simulation: SimulateTransaction.Value) -> [BalanceChange]? {
        guard let lamportsBefore = simulation.preBalances, let lamportsAfter = simulation.postBalances,
              let tokensBefore = simulation.preTokenBalances, let tokensAfter = simulation.postTokenBalances,
              lamportsBefore.count == transaction.accounts.count, lamportsAfter.count == transaction.accounts.count else {
            return nil
        }
        var changes = zip(transaction.accounts, zip(lamportsBefore, lamportsAfter)).compactMap { account, lamports in
            lamports.0 == lamports.1 ? nil : BalanceChange(owner: account.address, asset: .nativeSOL, before: lamports.0, after: lamports.1)
        }
        var holdings: [Holding] = []
        var totals: [Holding: Totals] = [:]
        for (balances, phase) in [(tokensBefore, \Totals.before), (tokensAfter, \Totals.after)] {
            for balance in balances {
                guard transaction.accounts.indices.contains(balance.accountIndex), let recordedOwner = balance.owner,
                      let owner = try? Address(recordedOwner), let mint = try? Address(balance.mint) else { return nil }
                let holding = Holding(owner: owner, asset: .token(mint: mint))
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

    /// One owner's balance in one asset.
    private struct Holding: Hashable {
        let owner: Address
        let asset: Asset.ID
    }

    /// Raw units summed across one holding's token accounts.
    private struct Totals {
        var before: UInt64 = 0
        var after: UInt64 = 0
    }
}
