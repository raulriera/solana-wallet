import Foundation
import Privacy
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
struct LocalBalanceMove {
    static let publicLamports: UInt64 = 2_000_000_000
    static let publicTokenAmount: UInt64 = 2_000_000_000
    static let privateAmount: UInt64 = 2_000_000_000
    static let amount: UInt64 = 1_000_000_000
    static let networkFee: UInt64 = 10_000
    static let registrationRent: UInt64 = 1_586_880

    let move: BalanceMove
    let model: TransactionReviewModel<BalanceMoveProposal>
    let balances: PrivateBalances
    let transactions: TransactionStore
    let preparation: HTTPResponses
    let sockets: SocketSequence

    var account: widgets.Account { move.account }

    static func deposit(
        of asset: PrivateAsset,
        registered: Bool = true,
        simulation: SimulateTransaction.Value? = nil,
        provider: RPCSettings.Provider = .helius,
        statuses: [GetSignatureStatuses.Response] = [],
        height: UInt64 = 500
    ) async throws -> LocalBalanceMove {
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
        var instructions = [try ShieldedPool.deposit(amount, of: asset, from: account.address, to: shielded.recipient, treeID: 1)]
        if !registered { instructions.insert(try shielded.register(paidBy: account.address), at: 0) }
        let spent = asset.lamports(moving: amount) + networkFee + (registered ? 0 : registrationRent)
        return try LocalBalanceMove(
            .toPrivate,
            of: asset,
            from: account,
            spendable: asset == .nativeSOL ? publicLamports : publicTokenAmount,
            balances: balances,
            simulation: try simulation
                ?? success(
                    of: instructions,
                    paidBy: account.address,
                    holding: publicLamports,
                    leaving: publicLamports - spent,
                    depositing: [:],
                    fixture: fixture
                ),
            fixture: fixture,
            statuses: statuses,
            height: height,
            sockets: SocketSequence()
        )
    }

    static func withdrawal(
        of asset: PrivateAsset,
        privateAmount: UInt64 = LocalBalanceMove.privateAmount,
        privacyFee: UInt64 = 0,
        accountDeposit: UInt64 = 0,
        statuses: [GetSignatureStatuses.Response] = [],
        sockets: SocketSequence = SocketSequence()
    ) async throws -> LocalBalanceMove {
        try await spend(.toPublic, of: asset, registry: [PrivateBalanceFixtures.unregistered],
                        privateAmount: privateAmount, privacyFee: privacyFee, accountDeposit: accountDeposit,
                        statuses: statuses, sockets: sockets)
    }

    static func send(
        of asset: PrivateAsset,
        publicLamports: UInt64 = LocalBalanceMove.publicLamports,
        privacyFee: UInt64 = 0,
        statuses: [GetSignatureStatuses.Response] = []
    ) async throws -> LocalBalanceMove {
        let recipient = try await PrivateBalanceFixtures.account(index: 1)
        let keys = try await PrivateBalanceFixtures.keys(for: recipient)
        let registry = try PrivateBalanceFixtures.registry(publishing: keys.shieldedAccount(for: recipient.address))
        return try await spend(.toRecipient(PaymentRecipient(address: recipient.address, name: "Alex"), warnings: []),
                               of: asset,
                               registry: [registry, PrivateBalanceFixtures.unregistered], publicLamports: publicLamports,
                               privacyFee: privacyFee, statuses: statuses)
    }

    private static func spend(
        _ direction: BalanceMoveProposal.Direction,
        of asset: PrivateAsset,
        registry: [String],
        publicLamports: UInt64 = LocalBalanceMove.publicLamports,
        privateAmount: UInt64 = LocalBalanceMove.privateAmount,
        privacyFee: UInt64,
        accountDeposit: UInt64 = 0,
        statuses: [GetSignatureStatuses.Response],
        sockets: SocketSequence = SocketSequence()
    ) async throws -> LocalBalanceMove {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let note = try PrivateBalanceFixtures.deposit(
            privateAmount,
            to: record.shieldedAccount(for: account.address),
            leafIndex: 1,
            of: asset
        )
        let balances = {
            PrivateBalances.inMemory(
                keys: StoredValue([account.address.value: record]),
                notes: StoredValue([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()]),
                recovery: try PrivateBalanceFixtures.recoveryStore(),
                responses: HTTPResponses.privateNotes(registry: registry, deposits: [note],
                                                      outputTreeID: 1, prover: try IndexedProofs.prover())
            )
        }
        let fixture = try SigningFixture()
        let (request, received): (PrivateTransactionRequest, UInt64) =
            switch direction {
            case .toRecipient(let recipient, _): (.send(amount, of: asset, to: recipient.address), 0)
            case .toPrivate, .toPublic: (.withdraw(amount, of: asset, to: account.address), asset.lamports(moving: amount))
            }
        let instructions = try await balances().prepare(request, from: account, on: .devnet).instructions
        let kept = publicLamports + received - networkFee - privacyFee - accountDeposit
        let deposits: [Address: UInt64] =
            switch asset {
            case .nativeSOL: [:]
            case .token(let token):
                [try TokenProgram.token.associatedAccount(owner: account.address, mint: token.mint): accountDeposit]
            }
        return try LocalBalanceMove(
            direction,
            of: asset,
            from: account,
            spendable: privateAmount,
            balances: try balances(),
            simulation: try success(
                of: instructions,
                paidBy: account.address,
                holding: publicLamports,
                leaving: kept,
                depositing: deposits,
                fixture: fixture
            ),
            fixture: fixture,
            statuses: statuses,
            sockets: sockets
        )
    }

    private init(
        _ direction: BalanceMoveProposal.Direction,
        of asset: PrivateAsset,
        from account: widgets.Account,
        spendable: UInt64,
        balances: PrivateBalances,
        simulation: SimulateTransaction.Value,
        fixture: SigningFixture,
        statuses: [GetSignatureStatuses.Response],
        height: UInt64 = 500,
        sockets: SocketSequence
    ) throws {
        var fixture = fixture
        fixture.simulation = SimulateTransaction.Response(context: Context(slot: 402), value: simulation)
        let recovery = try SigningRecoveryStore(recovery: PrivateBalanceFixtures.recovery())
        let local = try LocalTransactions(fixture: fixture, recovery: recovery, statuses: statuses, height: height,
                                          sockets: sockets)
        let coordinator = local.coordinator
        let transactions = TransactionStore.inMemory { _ in coordinator }
        let token: PaymentToken =
            switch asset {
            case .nativeSOL:
                PaymentToken(asset: .nativeSOL, balance: TokenAmount(lamports: spendable), price: nil)
            case .token(let token):
                PaymentFixtures.token(token.mint, decimals: 6, symbol: "USDC", balance: spendable, price: nil)
            }
        move = BalanceMove(
            direction: direction,
            token: token,
            privateAsset: asset,
            account: account,
            network: .devnet,
            balances: balances,
            transactions: transactions
        )
        move.payment.press(.digit(1))
        for _ in token.balance.decimals..<9 { move.payment.press(.digit(0)) }
        model = try move.review()
        self.balances = balances
        self.transactions = transactions
        preparation = local.preparation
        self.sockets = sockets
    }

    private static func success(of instructions: [Instruction], paidBy payer: Address, holding held: UInt64,
                                leaving kept: UInt64,
                                depositing deposits: [Address: UInt64],
                                fixture: SigningFixture) throws -> SimulateTransaction.Value {
        let message = try MessageBuilder().message(instructions: instructions, payer: payer,
                                                   recentBlockhash: fixture.blockhash.value.blockhash,
                                                   configuration: fixture.configuration)
        let others = try TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message))
            .accounts.dropFirst()
        return SimulateTransaction.Value(error: nil, logs: ["Program completed"], unitsConsumed: 150,
                                         loadedAccountsDataSize: 256, fee: networkFee, replacementBlockhash: nil,
                                         preBalances: [held] + others.map { _ in 0 },
                                         postBalances: [kept] + others.map { deposits[$0.address] ?? 0 },
                                         preTokenBalances: [], postTokenBalances: [])
    }
}
