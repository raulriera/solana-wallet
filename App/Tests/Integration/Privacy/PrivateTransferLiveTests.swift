import Foundation
import Privacy
import Testing
import Transactions
import Vault
import Wallet
@testable import RPC
@testable import widgets

@Suite(.tags(.network), .timeLimit(.minutes(10)))
struct PrivateTransferLiveTests {
    private static let depositLamports: UInt64 = 10_000_000

    private static let minimumPrivateLamports: UInt64 = 4_000_000

    private static let transferLamports: UInt64 = 2_000_000

    private static let feeLamports: UInt64 = 100_000

    @Test
    func `Private deposits, sends, and withdrawals move SOL between the test accounts`() async throws {
        async let configured = DevnetWallets.configured()
        async let store = RPCStore.inMemory(selection: .helius, key: try LiveClients.heliusAPIKey())
        let (wallets, rpcStore) = try await (configured, store)
        let rpc = SelectedRPCProvider(network: .devnet, rpcStore: rpcStore, rings: Zolana(network: .devnet))
        let sender = wallets.sender
        let recipient = wallets.recipient
        try await wallets.requireFunds(Self.feeLamports, using: rpc)
        let recovery = SigningRecoveryStore(recovery: wallets.recovery)
        let coordinator = try TransactionCoordinator(rpc: rpc, store: recovery, strategy: .none)
        let notes = StoredValue<PrivateBalances.Notes>()
        let balances = PrivateBalances(
            recovery: recovery, wallet: Wallet(),
            keys: StoredValue(), notes: notes, codes: StoredValue()
        ) { _ in rpc }

        let recipientKeys = try await wallets.shieldedAccount(of: recipient)
        let registration = try await recipientKeys.registration(using: rpc)
        try #require(registration != .registeredWithOtherKeys, "Account 1 registered other private-balance keys.")
        if registration == .unregistered {
            try await wallets.requireFunds(PrivateBalances.registrationLamports + Self.feeLamports, using: rpc)
            let confirmation = try await coordinator.run([try recipientKeys.register(paidBy: sender.address)],
                                                         signedBy: [sender, recipient])
            try #require(confirmation.outcome == .succeeded)
            try await Self.awaitRegistration(of: recipientKeys, using: rpc)
        }
        try await balances.enable(sender, on: .devnet)
        try await balances.enable(recipient, on: .devnet)

        var privateLamports = try await balances.settledBalance(of: sender, on: .devnet)
        if privateLamports < Self.minimumPrivateLamports {
            let deposit = try await balances.prepare(.deposit(Self.depositLamports), from: sender, on: .devnet)
            let rent = deposit.registers ? PrivateBalances.registrationLamports : 0
            try await wallets.requireFunds(Self.depositLamports + rent + Self.feeLamports, using: rpc)
            let confirmation = try await coordinator.run(deposit.instructions, signedBy: [sender])
            try #require(confirmation.outcome == .succeeded)
            #expect(try await balances.complete(deposit, with: confirmation).balance(of: .sol)
                == PrivateBalanceStatus.Balance(available: privateLamports, pending: Self.depositLamports))
            privateLamports = try await balances.settledBalance(of: sender, on: .devnet)
        }

        let send = try await balances.prepare(.send(Self.transferLamports, to: recipient.address), from: sender, on: .devnet)
        let sent = try await coordinator.run(send.instructions, signedBy: [sender])
        try #require(sent.outcome == .succeeded)
        let sentChange = try #require(send.effect.spend).receivedAmount
        #expect(try await balances.complete(send, with: sent).balance(of: .sol)
            == PrivateBalanceStatus.Balance(available: privateLamports - Self.transferLamports - sentChange, pending: sentChange))
        privateLamports = try await balances.settledBalance(of: sender, on: .devnet)

        let before = try await rpc.send(GetMultipleAccounts(addresses: [recipient.address.value]))
        let publicLamports = (before.value.first ?? nil)?.lamports ?? 0
        let withdrawal = try await balances.prepare(.withdraw(Self.transferLamports, to: recipient.address), from: sender,
                                                    on: .devnet)
        let withdrawn = try await coordinator.run(withdrawal.instructions, signedBy: [sender])
        try #require(withdrawn.outcome == .succeeded)
        let withdrawnChange = try #require(withdrawal.effect.spend).receivedAmount
        #expect(try await balances.complete(withdrawal, with: withdrawn).balance(of: .sol)
            == PrivateBalanceStatus.Balance(available: privateLamports - Self.transferLamports - withdrawnChange, pending: withdrawnChange))
        let slot = try await withdrawn.executionSlot(through: rpc)
        let after = try await rpc.send(GetMultipleAccounts(addresses: [recipient.address.value], minContextSlot: slot))
        #expect((after.value.first ?? nil)?.lamports == publicLamports + Self.transferLamports)
    }

    private static func awaitRegistration(of account: ShieldedAccount, using rpc: some RPC) async throws {
        let registered = try await poll { try await account.registration(using: rpc) == .registered ? true : nil }
        try #require(registered == true, "The registration wasn't finalized within a minute.")
    }
}
