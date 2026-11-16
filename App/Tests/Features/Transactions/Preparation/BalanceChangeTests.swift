import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

struct BalanceChangeTests {
    private static let mint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    private static let payer = "4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"
    private static let recipient = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
    private static let others = [
        "8CW93AFYFKj2rKZRq3YjLesb4XbgtAiq8k2FgfruVZL5", "GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL",
        "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", "11111111111111111111111111111111",
    ]

    @Test
    func `Changes report each account's SOL and each owner's summed token units`() throws {
        let transaction = try Self.transaction()
        let simulation = Self.value(
            before: [10_000_000, 0, 2_039_280, 2_039_280, 0, 1], after: [7_955_719, 1, 2_039_280, 2_039_280, 2_039_280, 1],
            tokensBefore: [Self.balance(index: 2, owner: Self.payer, amount: 300), Self.balance(index: 3, owner: Self.payer, amount: 200)],
            tokensAfter: [Self.balance(index: 2, owner: Self.payer, amount: 100), Self.balance(index: 3, owner: Self.payer, amount: 200),
                          Self.balance(index: 4, owner: Self.recipient, amount: 200)]
        )

        let changes = BalanceChange.changes(in: transaction, from: simulation)

        let token = Asset.ID.token(mint: try Address(Self.mint))
        #expect(changes == [
            BalanceChange(owner: try Address(Self.payer), asset: .nativeSOL, before: 10_000_000, after: 7_955_719),
            BalanceChange(owner: try Address(Self.recipient), asset: .nativeSOL, before: 0, after: 1),
            BalanceChange(owner: try Address(Self.others[2]), asset: .nativeSOL, before: 0, after: 2_039_280),
            BalanceChange(owner: try Address(Self.payer), asset: token, before: 500, after: 300),
            BalanceChange(owner: try Address(Self.recipient), asset: token, before: 0, after: 200),
        ])
    }

    @Test
    func `Unchanged balances are omitted`() throws {
        let simulation = Self.value(before: [5, 0, 1, 1, 1, 1], after: [5, 0, 1, 1, 1, 1],
                                    tokensBefore: [Self.balance(index: 2, owner: Self.payer, amount: 300)],
                                    tokensAfter: [Self.balance(index: 2, owner: Self.payer, amount: 300)])

        #expect(BalanceChange.changes(in: try Self.transaction(), from: simulation) == [])
    }

    @Test(arguments: [
        ("missing lamports after execution", BalanceChangeTests.value(after: nil)),
        ("missing token balances", BalanceChangeTests.value(tokensAfter: nil)),
        ("lamports for a different account count", BalanceChangeTests.value(after: [1, 2])),
        ("a token account outside the transaction",
         BalanceChangeTests.value(tokensAfter: [BalanceChangeTests.balance(index: 6, owner: BalanceChangeTests.payer, amount: 1)])),
        ("a token balance without an owner",
         BalanceChangeTests.value(tokensAfter: [BalanceChangeTests.balance(index: 2, owner: nil, amount: 1)])),
        ("a malformed owner",
         BalanceChangeTests.value(tokensAfter: [BalanceChangeTests.balance(index: 2, owner: "owner", amount: 1)])),
        ("a malformed mint",
         BalanceChangeTests.value(tokensAfter: [BalanceChangeTests.balance(index: 2, owner: BalanceChangeTests.payer, mint: "mint", amount: 1)])),
        ("summed units beyond the raw range", BalanceChangeTests.value(tokensAfter: [
            BalanceChangeTests.balance(index: 2, owner: BalanceChangeTests.payer, amount: .max),
            BalanceChangeTests.balance(index: 3, owner: BalanceChangeTests.payer, amount: 1),
        ])),
    ])
    func `Changes are unknown when balances are missing or can't be attributed`(reason: String, simulation: SimulateTransaction.Value) throws {
        #expect(BalanceChange.changes(in: try Self.transaction(), from: simulation) == nil, "\(reason)")
    }

    @Test
    func `A review exposes the balance changes its simulation observed`() async throws {
        var fixture = try SigningFixture()
        let payer = fixture.transfer.accounts[0].address
        let recipient = fixture.transfer.accounts[1].address
        fixture.simulation = .init(context: Context(slot: 402), value: .init(
            error: nil, logs: ["Program completed"], unitsConsumed: 150, loadedAccountsDataSize: 256, fee: 10_000,
            replacementBlockhash: nil, preBalances: [1_000_000, 0, 1], postBalances: [989_999, 1, 1],
            preTokenBalances: [], postTokenBalances: []
        ))
        let http = try HTTPResponses.preparation(fixture: fixture.preparation)
        let coordinator = try TransactionCoordinator(rpc: http.client, store: SigningRecoveryStore(recovery: fixture.recovery),
                                                     configuration: fixture.configuration)

        let review = try await coordinator.simulate([fixture.transfer], using: fixture.account)

        #expect(review.balanceChanges == [
            BalanceChange(owner: payer, asset: .nativeSOL, before: 1_000_000, after: 989_999),
            BalanceChange(owner: recipient, asset: .nativeSOL, before: 0, after: 1),
        ])
    }

    private static func transaction() throws -> Transaction {
        Transaction(message: Data(), lifetimeSpecifier: "11111111111111111111111111111111",
                    accounts: try ([payer, recipient] + others).map { .writable(try Address($0)) },
                    requests: .init(priorityFeeLamports: nil, computeUnitLimit: nil, loadedAccountsDataSizeLimit: nil, heapSize: nil),
                    instructions: [], signatures: [])
    }

    private static func value(before: [UInt64]? = [10, 0, 1, 1, 1, 1], after: [UInt64]? = [4, 1, 1, 1, 1, 1],
                              tokensBefore: [SimulateTransaction.TokenBalance]? = [],
                              tokensAfter: [SimulateTransaction.TokenBalance]? = []) -> SimulateTransaction.Value {
        SimulateTransaction.Value(error: nil, logs: [], unitsConsumed: 150, loadedAccountsDataSize: 256, fee: 5_000,
                                  replacementBlockhash: nil, preBalances: before, postBalances: after,
                                  preTokenBalances: tokensBefore, postTokenBalances: tokensAfter)
    }

    private static func balance(index: Int, owner: String?, mint: String = mint, amount: UInt64) -> SimulateTransaction.TokenBalance {
        SimulateTransaction.TokenBalance(accountIndex: index, mint: mint, owner: owner, amount: amount, decimals: 6)
    }
}
