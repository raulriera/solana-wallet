import Foundation
import Privacy
import Testing
import Transactions
import Vault
import Wallet
@testable import RPC
@testable import widgets

@Suite(.serialized, .tags(.network), .timeLimit(.minutes(10)))
struct RedeemCodeLiveTests {
    private static let depositLamports: UInt64 = 10_000_000

    private static let minimumPrivateLamports: UInt64 = 6_000_000

    private static let redeemedLamports: UInt64 = 2_000_000

    private static let takenBackLamports: UInt64 = 1_000_000

    private static let feeLamports: UInt64 = 100_000

    @Test
    func `Codes are redeemed and taken back to exactly zero lamports`() async throws {
        let wallets = try await DevnetWallets.configured()
        let providers = await ProviderStore.inMemory(selection: .helius, key: try LiveClients.heliusAPIKey())
        let rpc = ProviderClient(network: .devnet, providers: providers, rings: Zolana(network: .devnet))
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
        try await balances.enable(sender, on: .devnet)
        try await balances.enable(recipient, on: .devnet)
        try #require(try await balances.refresh(recipient, on: .devnet) != .unregistered,
                     "Run PrivateTransferLiveTests first so that account 1 is registered.")
        var log: [String] = []

        if try await Self.settledBalance(of: sender, in: balances) < Self.minimumPrivateLamports {
            let deposit = try await balances.prepare(.deposit(Self.depositLamports), from: sender, on: .devnet)
            try #require(!deposit.registers, "Run PrivateTransferLiveTests first so that account 0 is registered.")
            try await wallets.requireFunds(Self.depositLamports + Self.feeLamports, using: rpc)
            let (confirmation, _) = try await Self.run(deposit, through: coordinator)
            _ = try await balances.complete(deposit, with: confirmation)
            log.append("deposit \(confirmation.submission.signature)")
        }

        let redeemed = try await Self.createCode(of: Self.redeemedLamports, from: sender, in: balances, through: coordinator,
                                                 log: &log)
        let recipientLamports = try await Self.settledBalance(of: recipient, in: balances)
        let redemption = try await Self.preparedWhenIndexed(.redeem(redeemed.code), into: recipient, in: balances)
        let (redeemedConfirmation, charged) = try await Self.run(redemption, through: coordinator)
        let swept = try #require(Self.redemption(in: charged))
        #expect(try await balances.complete(charged, with: redeemedConfirmation) == .balance(available: recipientLamports, pending: swept.lamports))
        let redeemedFinal = try await Self.lamports(of: redeemed.code, after: redeemedConfirmation, using: rpc)
        log.append("redeem \(redeemedConfirmation.submission.signature) one-time final lamports \(redeemedFinal)")
        #expect(redeemedFinal == 0)
        #expect(swept.noteLamports == Self.redeemedLamports)
        #expect(swept.networkFee == Redemption.signatureFee)

        let takenBack = try await Self.createCode(of: Self.takenBackLamports, from: sender, in: balances,
                                                  through: coordinator, log: &log)
        let takeBack = try await Self.preparedWhenIndexed(.takeBack(index: takenBack.record.index), into: sender,
                                                          in: balances)
        let (takenBackConfirmation, chargedTakeBack) = try await Self.run(takeBack, through: coordinator)
        _ = try await balances.complete(chargedTakeBack, with: takenBackConfirmation)
        let takenBackFinal = try await Self.lamports(of: takenBack.code, after: takenBackConfirmation, using: rpc)
        log.append("take-back \(takenBackConfirmation.submission.signature) one-time final lamports \(takenBackFinal)")
        #expect(takenBackFinal == 0)
        #expect(try await !balances.outstandingCodes(of: sender, on: .devnet).map(\.record.index)
            .contains(takenBack.record.index))

        await #expect(throws: widgets.PrivateBalanceError.codeRedeemed) {
            try await balances.prepare(.redeem(takenBack.code), from: recipient, on: .devnet)
        }
        Attachment.record(log.joined(separator: "\n"), named: "Redeem code signatures")
    }

    private static func createCode(of lamports: UInt64, from sender: widgets.Account, in balances: PrivateBalances,
                                   through coordinator: TransactionCoordinator,
                                   log: inout [String]) async throws -> OutstandingRedeemCode {
        let prepared = try await balances.prepare(.createCode(lamports), from: sender, on: .devnet)
        guard case .createCode(_, let index, _) = prepared.effect else {
            return try #require(nil as OutstandingRedeemCode?, "Expected a code's creation.")
        }
        let (confirmation, _) = try await run(prepared, through: coordinator)
        _ = try await balances.complete(prepared, with: confirmation)
        log.append("create \(lamports) at index \(index) \(confirmation.submission.signature)")
        let outstanding = try await balances.outstandingCodes(of: sender, on: .devnet)
        return try #require(outstanding.first { $0.record.index == index }, "The new code isn't outstanding.")
    }

    private static func preparedWhenIndexed(_ request: PrivateTransactionRequest, into account: widgets.Account,
                                            in balances: PrivateBalances) async throws -> PreparedPrivateTransaction {
        for _ in 0..<30 {
            do {
                return try await balances.prepare(request, from: account, on: .devnet)
            } catch let error as widgets.PrivateBalanceError where error == .codeNotReady {
                try await Task.sleep(for: .seconds(2))
            }
        }
        return try #require(nil as PreparedPrivateTransaction?, "The indexer didn't report the code within a minute.")
    }

    private static func run(_ transaction: PreparedPrivateTransaction, through coordinator: TransactionCoordinator)
        async throws -> (widgets.Confirmation, PreparedPrivateTransaction) {
        let (simulation, charged) = try await coordinator.simulate(transaction)
        try #require(simulation.diagnostics.value.error == nil, "Simulation failed: \(simulation.diagnostics.value.logs ?? [])")
        let confirmation = try await coordinator.confirm(coordinator.submit(simulation))
        try #require(confirmation.outcome == .succeeded)
        return (confirmation, charged)
    }

    private static func lamports(of code: RedeemCode, after confirmation: widgets.Confirmation,
                                 using rpc: some RPC) async throws -> UInt64 {
        let address = try OneTimeAccount(secret: code.secret).address
        let slot = try await confirmation.executionSlot(through: rpc)
        let response = try await rpc.send(GetMultipleAccounts(addresses: [address], minContextSlot: slot))
        return (response.value.first ?? nil)?.lamports ?? 0
    }

    private static func redemption(in transaction: PreparedPrivateTransaction) -> Redemption? {
        guard case .redeem(let redemption) = transaction.effect else { return nil }
        return redemption
    }

    private static func settledBalance(of account: widgets.Account, in balances: PrivateBalances) async throws -> UInt64 {
        for _ in 0..<30 {
            if case .balance(let available, pending: 0) = try await balances.refresh(account, on: .devnet) {
                return available
            }
            try await Task.sleep(for: .seconds(2))
        }
        return try #require(nil as UInt64?, "The indexer didn't report the recorded transactions within a minute.")
    }
}
