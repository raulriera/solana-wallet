import Foundation
import Testing
import Transactions
import Wallet
@testable import Privacy
@testable import RPC
@testable import widgets

@Suite(.tags(.network), .timeLimit(.minutes(10)))
struct PrivateTokenLiveTests {
    private static let depositUnits: UInt64 = 100_000

    private static let withdrawalUnits: UInt64 = 40_000

    @Test
    func `Devnet USDC moves into the private balance and partly back to its owner`() async throws {
        async let configured = DevnetWallets.configured()
        async let store = RPCStore.inMemory(selection: .helius, key: try LiveClients.heliusAPIKey())
        let (wallets, rpcStore) = try await (configured, store)
        let rpc = SelectedRPCProvider(network: .devnet, rpcStore: rpcStore, rings: Zolana(network: .devnet))
        let owner = wallets.sender
        let coordinator = try TransactionCoordinator(rpc: rpc, store: SigningRecoveryStore(recovery: wallets.recovery),
                                                     strategy: .none)
        let shielded = try await wallets.shieldedAccount(of: owner)
        try #require(try await shielded.registration(using: rpc) == .registered, "The first test account must have a private balance.")
        let tokenAccount = try TokenProgram.token.associatedAccount(owner: owner.address, mint: PrivateToken.devnetUSDC.mint)
        var state = try await NoteSyncState().syncedToEnd(for: shielded, rpc: rpc, indexer: rpc)

        let deposit = try ShieldedPool.deposit(Self.depositUnits, of: .devnetUSDC, from: owner.address, to: shielded.recipient,
                                               treeID: try #require(state.outputTreeID))
        let deposited = try await coordinator.run([deposit], signedBy: [owner])
        try #require(deposited.outcome == .succeeded)
        let beforeDeposit = state.spendableAmount(of: .devnetUSDC)
        state = try state.recording(depositOf: Self.depositUnits, of: .devnetUSDC, signature: deposited.submission.signature)
        #expect(state.pendingAmount(of: .devnetUSDC) == Self.depositUnits)
        state = try await Self.settled(state, of: shielded, using: rpc)
        #expect(state.spendableAmount(of: .devnetUSDC) == beforeDeposit + Self.depositUnits)

        let funded = state
        let spendable = funded.spendableAmount(of: .devnetUSDC)
        async let publicRead = Self.balance(of: tokenAccount, using: rpc)
        async let proved = funded.spend(Self.withdrawalUnits, to: .tokenWithdrawal(.devnetUSDC, owner: owner.address),
                                        from: shielded, rpc: rpc, prover: rpc)
        let (publicUnits, spend) = try await (publicRead, proved)
        let withdrawn = try await coordinator.run([spend.instruction], signedBy: [owner])
        try #require(withdrawn.outcome == .succeeded)
        let slot = try #require(withdrawn.slot)
        #expect(try await Self.balance(of: tokenAccount, using: rpc, minContextSlot: slot) == publicUnits + Self.withdrawalUnits)
        state = try funded.recording(spend, signature: withdrawn.submission.signature)
        #expect(state.pendingAmount(of: .devnetUSDC) == spend.receivedAmount)
        state = try await Self.settled(state, of: shielded, using: rpc)
        #expect(state.spendableAmount(of: .devnetUSDC) == spendable - Self.withdrawalUnits)
    }

    @Test
    func `A devnet USDC withdrawal opens a missing token account in the same transaction`() async throws {
        async let configured = DevnetWallets.configured()
        async let store = RPCStore.inMemory(selection: .helius, key: try LiveClients.heliusAPIKey())
        let (wallets, rpcStore) = try await (configured, store)
        let rpc = SelectedRPCProvider(network: .devnet, rpcStore: rpcStore, rings: Zolana(network: .devnet))
        let (owner, recipient) = (wallets.sender, wallets.recipient)
        let mint = try PrivateToken.devnetUSDC.mint
        let tokenAccount = try TokenProgram.token.associatedAccount(owner: recipient.address, mint: mint)
        let accounts = try await rpc.accounts(at: [tokenAccount.value, mint.value])
        try #require(accounts.value[0] == nil, "The second test account must have no devnet USDC account.")
        let mintAccount = try #require(accounts.value[1])
        let tokenMint = try TokenMint(address: mint, owner: Address(mintAccount.owner), data: mintAccount.data)
        let recovery = SigningRecoveryStore(recovery: wallets.recovery)
        let coordinator = try TransactionCoordinator(rpc: rpc, store: recovery, strategy: .none)
        let balances = PrivateBalances(recovery: recovery, wallet: Wallet(), keys: StoredValue(), notes: StoredValue(),
                                       codes: StoredValue()) { _ in rpc }
        try await balances.enable(owner, on: .devnet)
        let status = try await balances.refresh(owner, on: .devnet)
        try #require((status.balance(of: .token(.devnetUSDC))?.available ?? 0) > 0, "The first test account must hold private devnet USDC.")

        let withdrawal = try await balances.prepare(.withdraw(1, of: .token(.devnetUSDC), to: recipient.address), from: owner,
                                                    on: .devnet)
        let (simulation, _) = try await coordinator.simulate(withdrawal)

        #expect(withdrawal.instructions.first
            == (try AssociatedTokenProgram.createIdempotent(owner: recipient.address, mint: mint, program: .token, payer: owner.address)))
        #expect(simulation.diagnostics.value.error == nil)
        let rent = try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: tokenMint.associatedAccountSize))
        #expect(simulation.balanceChanges?.contains(BalanceChange(owner: tokenAccount, asset: .sol, before: 0, after: rent)) == true)
    }

    private static func settled(
        _ state: NoteSyncState, of account: ShieldedAccount, using rpc: SelectedRPCProvider
    ) async throws -> NoteSyncState {
        let settled = try await poll {
            let next = try await state.syncedToEnd(for: account, rpc: rpc, indexer: rpc)
            return next.pendingAmount(of: .devnetUSDC) == 0 && !next.hasUnconfirmedNotes ? next : nil
        }
        return try #require(settled, "The indexer didn't report the recorded transaction within a minute.")
    }

    private static func balance(
        of tokenAccount: Address, using rpc: some RPC, minContextSlot: UInt64? = nil
    ) async throws -> UInt64 {
        let response = try await rpc.accounts(at: [tokenAccount.value], minContextSlot: minContextSlot)
        let account = try #require(response.value.first ?? nil)
        return try TokenAccount(address: tokenAccount, programOwner: Address(account.owner), data: account.data).amount
    }
}
