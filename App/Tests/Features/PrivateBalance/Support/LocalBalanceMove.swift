import Foundation
import Privacy
@testable import RPC
import Transactions
@testable import widgets

/// The review of a fixture account's 1 SOL devnet move between its balances, over real private balances and a real
/// transaction coordinator that answer from local responses and sockets, whose shared transactions keep records in
/// memory.
///
/// A deposit moves 1 SOL from a public balance of 2 SOL; a withdrawal moves 1 SOL from one private note to the same
/// public balance. Every simulation reports a 10,000-lamport network fee.
@MainActor
struct LocalBalanceMove {
    /// The account's public SOL, in lamports.
    static let publicLamports: UInt64 = 2_000_000_000
    /// The account's private SOL of a withdrawal, one note, in lamports, unless a test picks another.
    static let privateLamports: UInt64 = 2_000_000_000
    /// The typed amount, in lamports.
    static let lamports: UInt64 = 1_000_000_000
    /// The network fee of every simulation, in lamports.
    static let networkFee: UInt64 = 10_000
    /// The rent of the registry record that an account's first deposit creates, in lamports.
    static let registrationRent: UInt64 = 1_823_520

    /// The open move, with 1 SOL typed.
    let move: BalanceMove
    /// The move's review under test, before it's proved and simulated.
    let model: TransactionReviewModel<BalanceMoveProposal>
    /// The private balances, which prepare the move and record its outcome.
    let balances: PrivateBalances
    /// The shared transactions, which send, record, and watch the move.
    let transactions: TransactionStore
    /// The responses that answer the coordinator's preparation reads and simulations.
    let preparation: HTTPResponses
    /// The connections of the coordinator's watch.
    let sockets: SocketSequence

    /// The account whose SOL moves.
    var account: widgets.Account { move.account }

    /// Creates the review of a deposit of 1 SOL.
    /// - Parameters:
    ///   - registered: Whether the account registered its keys before; otherwise the deposit registers them.
    ///   - simulation: The simulated execution of every deposit, or `nil` for a success that reports the payer's SOL.
    ///   - provider: The selected provider of the private balances.
    ///   - statuses: The watch's status reads, in arrival order.
    ///   - height: The finalized block height of the watch's epoch reads.
    ///   - sockets: The watch's connections.
    /// - Returns: The deposit's review and the local responses and connections behind it.
    /// - Throws: A fixture error.
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
        // The payer's SOL pays the deposit, the network fee, and a first deposit's registration.
        let spent = lamports + networkFee + (registered ? 0 : registrationRent)
        return try LocalBalanceMove(
            .toPrivate, of: account, spendableLamports: publicLamports, balances: balances,
            simulation: try simulation ?? success(of: instructions, paidBy: account.address,
                                                  leaving: publicLamports - spent, fixture: fixture),
            fixture: fixture, statuses: statuses, height: height, sockets: sockets
        )
    }

    /// Creates the review of a withdrawal of 1 SOL from one private note to the account's own public address.
    /// - Parameters:
    ///   - privateLamports: The SOL of the account's one private note, in lamports.
    ///   - privacyFee: The pool's fee that the successful simulation charges the payer, in lamports.
    ///   - simulation: The simulated execution of every withdrawal, or `nil` for a success that reports the payer's SOL.
    ///   - statuses: The watch's status reads, in arrival order.
    ///   - sockets: The watch's connections.
    /// - Returns: The withdrawal's review and the local responses and connections behind it.
    /// - Throws: A fixture or preparation error.
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
                // The note's nullifier account doesn't exist, so no transact has queued it.
                responses: HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered], deposits: [note],
                                                      outputTreeID: 1, prove: PrivateBalanceFixtures.proof(answering:))
            )
        }
        let fixture = try SigningFixture()
        // A separate preparation finds the withdrawal's accounts, whose balances the simulation reports.
        let instructions = try await balances().prepare(.withdraw(lamports, to: account.address), from: account,
                                                        on: .devnet).instructions
        // The payer's SOL receives the withdrawal and pays the network fee and the privacy fee.
        let kept = publicLamports + lamports - networkFee - privacyFee
        return try LocalBalanceMove(
            .toPublic, of: account, spendableLamports: privateLamports, balances: try balances(),
            simulation: try simulation ?? success(of: instructions, paidBy: account.address, leaving: kept,
                                                  fixture: fixture),
            fixture: fixture, statuses: statuses, sockets: sockets
        )
    }

    /// Creates a move with 1 SOL typed and its review, over a transaction coordinator that answers from local
    /// responses and sockets.
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves, and which one it reaches.
    ///   - account: The account whose SOL moves.
    ///   - spendableLamports: The SOL of the balance that the SOL leaves, in lamports.
    ///   - balances: The private balances.
    ///   - simulation: The simulated execution of every move.
    ///   - fixture: The blockhash and resource requests that the transaction compiles with.
    ///   - statuses: The watch's status reads, in arrival order.
    ///   - height: The finalized block height of the watch's epoch reads.
    ///   - sockets: The watch's connections.
    /// - Throws: A fixture error.
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

    /// Creates a successful simulation of a move, whose payer starts with the public balance.
    /// - Parameters:
    ///   - instructions: The move's instructions.
    ///   - payer: The account that pays.
    ///   - kept: The payer's SOL after the move, in lamports.
    ///   - fixture: The blockhash and resource requests that the transaction compiles with.
    /// - Returns: The execution, with balances for every account of the compiled transaction.
    /// - Throws: A compilation error, which doesn't happen.
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
