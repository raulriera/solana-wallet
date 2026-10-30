import Foundation
import Privacy
@testable import RPC
import Transactions
@testable import widgets

@MainActor
struct LocalBalanceMove {
    static let publicLamports: UInt64 = 2_000_000_000
    static let privateLamports: UInt64 = 2_000_000_000
    static let lamports: UInt64 = 1_000_000_000
    static let networkFee: UInt64 = 10_000
    static let registrationRent: UInt64 = 1_586_880

    let move: BalanceMove
    let model: TransactionReviewModel<BalanceMoveProposal>
    let balances: PrivateBalances
    let transactions: TransactionStore
    let preparation: HTTPResponses
    let sockets: SocketSequence

    var account: widgets.Account { move.account }

    static func deposit(registered: Bool = true, simulation: SimulateTransaction.Value? = nil,
                        provider: ProviderSettings.Provider = .helius, statuses: [GetSignatureStatuses.Response] = [],
                        height: UInt64 = 500,
                        sockets: SocketSequence = SocketSequence()) async throws -> LocalBalanceMove {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try record.shieldedAccount(for: account.address)
        let notes = registered
            ? StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
            : StoredValue<PrivateBalances.Notes>()
        let balances = PrivateBalances.inMemory(
            keys: StoredValue([account.address.value: record]), notes: notes,
            recovery: try PrivateBalanceFixtures.recoveryStore(),
            responses: HTTPResponses.privateNotes(registry: registered ? [] : [PrivateBalanceFixtures.unregistered],
                                                  outputTreeID: 1),
            provider: provider
        )
        let fixture = try SigningFixture()
        var instructions = [try ShieldedPool.deposit(lamports: lamports, from: account.address, to: shielded.recipient,
                                                     treeID: 1)]
        if !registered { instructions.insert(try shielded.register(paidBy: account.address), at: 0) }
        let spent = lamports + networkFee + (registered ? 0 : registrationRent)
        return try LocalBalanceMove(
            .toPrivate, of: account, spendableLamports: publicLamports, balances: balances,
            simulation: try simulation ?? success(of: instructions, paidBy: account.address,
                                                  leaving: publicLamports - spent, fixture: fixture),
            fixture: fixture, statuses: statuses, height: height, sockets: sockets
        )
    }

    static func withdrawal(privateLamports: UInt64 = LocalBalanceMove.privateLamports, privacyFee: UInt64 = 0,
                           simulation: SimulateTransaction.Value? = nil,
                           statuses: [GetSignatureStatuses.Response] = [],
                           sockets: SocketSequence = SocketSequence()) async throws -> LocalBalanceMove {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let note = try PrivateBalanceFixtures.deposit(privateLamports, to: record.shieldedAccount(for: account.address),
                                                      leafIndex: 1)
        let balances = {
            PrivateBalances.inMemory(
                keys: StoredValue([account.address.value: record]),
                notes: StoredValue([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()]),
                recovery: try PrivateBalanceFixtures.recoveryStore(),
                responses: HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered], deposits: [note],
                                                      outputTreeID: 1, prove: PrivateBalanceFixtures.proof(answering:))
            )
        }
        let fixture = try SigningFixture()
        let instructions = try await balances().prepare(.withdraw(lamports, to: account.address), from: account,
                                                        on: .devnet).instructions
        let kept = publicLamports + lamports - networkFee - privacyFee
        return try LocalBalanceMove(
            .toPublic, of: account, spendableLamports: privateLamports, balances: try balances(),
            simulation: try simulation ?? success(of: instructions, paidBy: account.address, leaving: kept,
                                                  fixture: fixture),
            fixture: fixture, statuses: statuses, sockets: sockets
        )
    }

    private init(_ direction: BalanceMoveProposal.Direction, of account: widgets.Account, spendableLamports: UInt64,
                 balances: PrivateBalances, simulation: SimulateTransaction.Value, fixture: SigningFixture,
                 statuses: [GetSignatureStatuses.Response], height: UInt64 = 500, sockets: SocketSequence) throws {
        var fixture = fixture
        fixture.simulation = SimulateTransaction.Response(context: Context(slot: 402), value: simulation)
        let recovery = try SigningRecoveryStore(recovery: PrivateBalanceFixtures.recovery())
        let local = try LocalTransactions(fixture: fixture, recovery: recovery, statuses: statuses, height: height,
                                          sockets: sockets)
        let coordinator = local.coordinator
        let transactions = TransactionStore.inMemory { _ in coordinator }
        move = BalanceMove(direction: direction, account: account, network: .devnet,
                           spendableLamports: spendableLamports, balances: balances, transactions: transactions)
        move.payment.press(.digit(1))
        model = try move.review()
        self.balances = balances
        self.transactions = transactions
        preparation = local.preparation
        self.sockets = sockets
    }

    private static func success(of instructions: [Instruction], paidBy payer: Address, leaving kept: UInt64,
                                fixture: SigningFixture) throws -> SimulateTransaction.Value {
        let message = try MessageBuilder().message(instructions: instructions, payer: payer,
                                                   recentBlockhash: fixture.blockhash.value.blockhash,
                                                   configuration: fixture.configuration)
        let others = try TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message))
            .accounts.dropFirst().map { _ in UInt64(0) }
        return SimulateTransaction.Value(error: nil, logs: ["Program completed"], unitsConsumed: 150,
                                         loadedAccountsDataSize: 256, fee: networkFee, replacementBlockhash: nil,
                                         preBalances: [publicLamports] + others, postBalances: [kept] + others,
                                         preTokenBalances: [], postTokenBalances: [])
    }
}
