import Foundation
import Privacy
import Testing
import Transactions
import Vault
import Wallet
@testable import RPC
@testable import widgets

@Suite(.serialized, .tags(.network), .timeLimit(.minutes(10)))
struct PrivateTransferLiveTests {
    private static let depositLamports: UInt64 = 10_000_000

    private static let minimumPrivateLamports: UInt64 = 4_000_000

    private static let transferLamports: UInt64 = 2_000_000

    private static let registrationLamports: UInt64 = 1_330_960

    private static let feeLamports: UInt64 = 100_000

    @Test(arguments: [ProviderSettings.Provider.helius, .solana])
    func `Private deposits, sends, and withdrawals move SOL between the test accounts`(
        provider: ProviderSettings.Provider
    ) async throws {
        let wallets = try await DevnetWallets.configured()
        let apiKey = provider == .helius ? try LiveClients.heliusAPIKey() : nil
        let providers = await ProviderStore.inMemory(selection: provider, key: apiKey)
        let rpc = ProviderClient(network: .devnet, providers: providers)
        let sender = wallets.sender
        let recipient = wallets.recipient
        try await wallets.requireFunds(Self.feeLamports, using: rpc)
        let coordinator = try TransactionCoordinator(rpc: rpc, store: SigningRecoveryStore(recovery: wallets.recovery),
                                                     strategy: .none)
        let notes = StoredValue<PrivateBalances.Notes>()
        let balances = PrivateBalances(
            recovery: SecurityRecoveryStore(records: [sender.recoveryID: wallets.recovery]), wallet: Wallet(),
            keys: StoredValue(), notes: notes, codes: StoredValue()
        ) { _ in rpc }

        let recipientKeys = try await Self.keys(of: recipient, from: wallets)
        switch try await recipientKeys.registration(using: rpc) {
        case .unregistered:
            try await wallets.requireFunds(Self.registrationLamports + Self.feeLamports, using: rpc)
            let confirmation = try await Self.run([try recipientKeys.register(paidBy: sender.address)],
                                                  signedBy: [sender, recipient], through: coordinator)
            try #require(confirmation.outcome == .succeeded)
            try await Self.awaitRegistration(of: recipientKeys, using: rpc)
        case .registeredWithOtherKeys:
            Issue.record("Account 1 registered other private-balance keys.")
            return
        case .registered:
            break
        }
        try await balances.enable(sender, on: .devnet)
        try await balances.enable(recipient, on: .devnet)

        var privateLamports = try await Self.settledBalance(of: sender, in: balances)
        if privateLamports < Self.minimumPrivateLamports {
            let deposit = try await balances.prepare(.deposit(Self.depositLamports), from: sender, on: .devnet)
            let rent = deposit.registers ? Self.registrationLamports : 0
            try await wallets.requireFunds(Self.depositLamports + rent + Self.feeLamports, using: rpc)
            let confirmation = try await Self.run(deposit.instructions, signedBy: [sender], through: coordinator)
            try #require(confirmation.outcome == .succeeded)
            #expect(try await balances.complete(deposit, with: confirmation) == .balance(available: privateLamports, pending: Self.depositLamports))
            privateLamports = try await Self.settledBalance(of: sender, in: balances)
        }

        let send = try await balances.prepare(.send(Self.transferLamports, to: recipient.address), from: sender, on: .devnet)
        let sent = try await Self.run(send.instructions, signedBy: [sender], through: coordinator)
        try #require(sent.outcome == .succeeded)
        let sentChange = Self.change(of: send)
        #expect(try await balances.complete(send, with: sent)
            == .balance(available: privateLamports - Self.transferLamports - sentChange, pending: sentChange))
        privateLamports = try await Self.settledBalance(of: sender, in: balances)

        let before = try await rpc.send(GetMultipleAccounts(addresses: [recipient.address.value]))
        let publicLamports = (before.value.first ?? nil)?.lamports ?? 0
        let withdrawal = try await balances.prepare(.withdraw(Self.transferLamports, to: recipient.address), from: sender,
                                                    on: .devnet)
        let withdrawn = try await Self.run(withdrawal.instructions, signedBy: [sender], through: coordinator)
        try #require(withdrawn.outcome == .succeeded)
        let withdrawnChange = Self.change(of: withdrawal)
        #expect(try await balances.complete(withdrawal, with: withdrawn)
            == .balance(available: privateLamports - Self.transferLamports - withdrawnChange, pending: withdrawnChange))
        let slot = try await withdrawn.executionSlot(through: rpc)
        let after = try await rpc.send(GetMultipleAccounts(addresses: [recipient.address.value], minContextSlot: slot))
        #expect((after.value.first ?? nil)?.lamports == publicLamports + Self.transferLamports)
    }

    private static func awaitRegistration(of account: ShieldedAccount, using rpc: some RPC) async throws {
        for _ in 0..<30 {
            if try await account.registration(using: rpc) == .registered { return }
            try await Task.sleep(for: .seconds(2))
        }
        try #require(try await account.registration(using: rpc) == .registered, "The registration wasn't finalized within a minute.")
    }

    private static func keys(of account: widgets.Account, from wallets: DevnetWallets) async throws -> ShieldedAccount {
        try PrivateBalanceKeyRecord(try await Wallet().privateBalanceKeys(
            using: wallets.recovery.phrase, expectedAddress: account.address.value, passphrase: wallets.recovery.passphrase,
            path: account.path
        )).shieldedAccount(for: account.address)
    }

    private static func run(_ instructions: [Instruction], signedBy signers: [widgets.Account],
                            through coordinator: TransactionCoordinator) async throws -> widgets.Confirmation {
        let simulation = try await coordinator.simulate(instructions, using: signers)
        try #require(simulation.diagnostics.value.error == nil, "Simulation failed: \(simulation.diagnostics.value.logs ?? [])")
        return try await coordinator.confirm(coordinator.submit(simulation))
    }

    private static func change(of transaction: PreparedPrivateTransaction) -> UInt64 {
        guard case .spend(let spend) = transaction.effect else { return 0 }
        return spend.receivedLamports
    }

    private static func settledBalance(of account: widgets.Account, in balances: PrivateBalances) async throws -> UInt64 {
        for _ in 0..<30 {
            let status = try await balances.refresh(account, on: .devnet)
            if case .unregistered = status { return 0 }
            if case .balance(let available, pending: 0) = status { return available }
            try await Task.sleep(for: .seconds(2))
        }
        return try #require(nil as UInt64?, "The indexer didn't report the recorded transactions within a minute.")
    }
}
