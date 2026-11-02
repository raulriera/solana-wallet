import Foundation
import Privacy
import Storage
import Testing
import Transactions
import Wallet
@testable import RPC
@testable import widgets

@Suite(.timeLimit(.minutes(1)))
struct PrivateBalancesTests {
    @Test(arguments: Network.allCases)
    func `Enabling keeps the keys of an unregistered account`(network: Network) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let recovery = try PrivateBalanceFixtures.recoveryStore()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let keys = StoredValue<PrivateBalances.Keys>()
        let notes = StoredValue<PrivateBalances.Notes>()

        try await Self.balances(responses, recovery: recovery, keys: keys, notes: notes).enable(account, on: network)

        #expect(await keys.value == [account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        #expect(await notes.value == nil)
        #expect(await recovery.reads == [PrivateBalanceFixtures.recoveryID])
        #expect(try await Self.methods(of: responses) == [GetMultipleAccounts.method])
    }

    @Test
    func `Enabling keeps other accounts' keys`() async throws {
        async let derivedFirst = PrivateBalanceFixtures.account(index: 0)
        async let derivedSecond = PrivateBalanceFixtures.account(index: 1)
        let (first, second) = try await (derivedFirst, derivedSecond)
        let firstKeys = try await PrivateBalanceFixtures.keys(for: first)
        let keys = StoredValue<PrivateBalances.Keys>([first.address.value: firstKeys])
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])

        try await Self.balances(responses, keys: keys).enable(second, on: .devnet)

        #expect(await keys.value == [first.address.value: firstKeys,
                                     second.address.value: try await PrivateBalanceFixtures.keys(for: second)])
    }

    @Test
    func `Enabling an account registered with its own keys keeps its keys and notes entry`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let responses = HTTPResponses.privateNotes(registry: [registry])
        let keys = StoredValue<PrivateBalances.Keys>()
        let notes = StoredValue<PrivateBalances.Notes>()

        try await Self.balances(responses, keys: keys, notes: notes).enable(account, on: .devnet)

        #expect(await keys.value == [account.address.value: record])
        #expect(await notes.value == [PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        #expect(try await Self.methods(of: responses) == [GetMultipleAccounts.method])
    }

    @Test
    func `Enabling with a custom RPC off mainnet keeps the keys unchecked`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let keys = StoredValue<PrivateBalances.Keys>()
        let notes = StoredValue<PrivateBalances.Notes>()

        try await Self.balances(responses, provider: try PrivateBalanceFixtures.customRPC(), keys: keys, notes: notes)
            .enable(account, on: .devnet)

        #expect(await keys.value == [account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        #expect(await notes.value == nil)
        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `Enabling an account at another path prompts nothing and throws`() async throws {
        let fixture = try await PrivateBalanceFixtures.account()
        let account = widgets.Account(id: UUID(), recoveryID: PrivateBalanceFixtures.recoveryID, address: fixture.address,
                                      path: try DerivationPath("m/44'/501'/0'"))
        let recovery = try PrivateBalanceFixtures.recoveryStore()
        let responses = HTTPResponses.privateNotes()
        let keys = StoredValue<PrivateBalances.Keys>()

        await #expect(throws: PrivateBalanceError.unsupportedAccount) {
            try await Self.balances(responses, recovery: recovery, keys: keys).enable(account, on: .devnet)
        }
        #expect(await recovery.reads.isEmpty)
        #expect(await keys.value == nil)
        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `A reset during enabling leaves no keys`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(
            registry: [try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))],
            gate: gate, heldMethod: GetMultipleAccounts.method
        )
        let keys = StoredValue<PrivateBalances.Keys>()
        let notes = StoredValue<PrivateBalances.Notes>()
        let balances = try await Self.balances(responses, keys: keys, notes: notes)

        let enabling = Task { try await balances.enable(account, on: .devnet) }
        await gate.waitUntilStarted()
        try await balances.removeAll()
        gate.resume()

        await #expect(throws: CancellationError.self) { try await enabling.value }
        #expect(await keys.value == nil)
        #expect(await notes.value == nil)
    }

    @Test
    func `Enabling rejects an account registered with other keys`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let other = try PrivateBalanceFixtures.otherKeys(for: account.address)
        let responses = HTTPResponses.privateNotes(registry: [try PrivateBalanceFixtures.registry(publishing: other)])
        let keys = StoredValue<PrivateBalances.Keys>()

        await #expect(throws: PrivateBalanceError.registeredWithOtherKeys) {
            try await Self.balances(responses, keys: keys).enable(account, on: .devnet)
        }
        #expect(await keys.value == nil)
    }

    @Test
    func `Enabling saves nothing when recovery can't be read`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let keys = StoredValue<PrivateBalances.Keys>()

        await #expect(throws: CancellationError.self) {
            try await Self.balances(responses, recovery: SecurityRecoveryStore(readError: CancellationError()),
                                    keys: keys)
                .enable(account, on: .devnet)
        }
        #expect(await keys.value == nil)
        #expect(await responses.requests.isEmpty)
    }

    @Test(arguments: [false, true])
    func `Refreshing an account without keys is off and reads its registration`(isRegistered: Bool) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let shielded = try await PrivateBalanceFixtures.keys(for: account).shieldedAccount(for: account.address)
        let registry = isRegistered ? try PrivateBalanceFixtures.registry(publishing: shielded)
                                    : PrivateBalanceFixtures.unregistered
        let responses = HTTPResponses.privateNotes(registry: [registry])

        #expect(try await Self.balances(responses).refresh(account, on: .devnet) == .off(isRegistered: isRegistered))
        #expect(try await Self.methods(of: responses) == [GetMultipleAccounts.method])
    }

    @Test
    func `An unread registry shows private balances off`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes(error: .http(statusCode: 429, retryAfter: "3"))

        #expect(try await Self.balances(responses).refresh(account, on: .devnet) == .off(isRegistered: false))
    }

    @Test
    func `An account without keys is unavailable with a custom RPC off mainnet`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let balances = try await Self.balances(responses, provider: try PrivateBalanceFixtures.customRPC())

        #expect(try await balances.refresh(account, on: .devnet) == .unavailable)
        #expect(await responses.requests.isEmpty)
    }

    @Test(arguments: zip([ProviderSettings.Provider.helius, .solana], [Network.devnet, .mainnet]))
    func `A registered account syncs and saves its notes, checking registration once`(
        provider: ProviderSettings.Provider, network: Network
    ) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try record.shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(
            registry: [try PrivateBalanceFixtures.registry(publishing: shielded)],
            deposits: [try PrivateBalanceFixtures.deposit(1_000_000, to: shielded, leafIndex: 4)]
        )
        let notes = StoredValue<PrivateBalances.Notes>()
        let balances = try await Self.balances(responses, provider: provider,
                                               keys: StoredValue([account.address.value: record]), notes: notes)
        let id = PrivateBalances.noteID(of: account, on: network)

        let first = try await balances.refresh(account, on: network)
        let saved = await notes.value?[id]
        let later = try await balances.refresh(account, on: network)

        #expect(first == .balance(available: 1_000_000, pending: 0))
        #expect(later == .balance(available: 1_000_000, pending: 0))
        #expect(saved?.lamports == 1_000_000)
        #expect(await notes.value?[id] == saved)
        #expect(await PrivateBalanceFixtures.nonTreeAccountReads(of: responses) == 1)
        #expect(try await Self.methods(of: responses).filter { $0 == GetMerkleProofs.method }.count == 1)
        #expect(try await Self.tagCursors(of: responses) == [nil, HTTPResponses.indexerPosition])
    }

    @Test
    func `Notes whose roots aren't on chain yet count after a later refresh finds them`() async throws {
        let registered = try await Self.registeredAccount(index: 0, lamports: 1_000_000)
        let keys = StoredValue([registered.account.address.value: registered.keys])
        let id = PrivateBalances.noteID(of: registered.account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let lagging = HTTPResponses.privateNotes(deposits: [registered.deposit],
                                                 trees: UTXOTrees(rows: [registered.deposit], isFinalized: false))
        let finalized = HTTPResponses.privateNotes(trees: UTXOTrees(rows: [registered.deposit]))

        let first = try await Self.balances(lagging, keys: keys, notes: notes).refresh(registered.account, on: .devnet)
        let unconfirmed = await notes.value?[id]
        let later = try await Self.balances(finalized, keys: keys, notes: notes).refresh(registered.account, on: .devnet)

        #expect(first == .balance(available: 0, pending: 0))
        #expect(unconfirmed?.notes.isEmpty == true)
        #expect(later == .balance(available: 1_000_000, pending: 0))
        #expect(await notes.value?[id]?.notes.map(\.signature) == [RedeemCodeFixtures.signature(ofDepositAt: 1)])
        #expect(try await Self.methods(of: finalized).contains(GetMerkleProofs.method))
    }

    @Test
    func `Notes whose proofs don't lead to their roots never count`() async throws {
        let registered = try await Self.registeredAccount(index: 0, lamports: 1_000_000)
        let shielded = try registered.keys.shieldedAccount(for: registered.account.address)
        let forged = try PrivateBalanceFixtures.deposit(5_000_000, to: shielded, leafIndex: 7)
        let keys = StoredValue([registered.account.address.value: registered.keys])
        let id = PrivateBalances.noteID(of: registered.account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let responses = HTTPResponses.privateNotes(deposits: [registered.deposit, forged],
                                                   trees: UTXOTrees(rows: [registered.deposit], forging: [forged]))
        let later = HTTPResponses.privateNotes()

        let first = try await Self.balances(responses, keys: keys, notes: notes).refresh(registered.account, on: .devnet)
        let second = try await Self.balances(later, keys: keys, notes: notes).refresh(registered.account, on: .devnet)

        #expect(first == .balance(available: 1_000_000, pending: 0))
        #expect(second == .balance(available: 1_000_000, pending: 0))
        #expect(await notes.value?[id]?.notes.map(\.signature) == [RedeemCodeFixtures.signature(ofDepositAt: 1)])
        #expect(try await !Self.methods(of: later).contains(GetMerkleProofs.method))
    }

    @Test
    func `Spent unconfirmed notes never count`() async throws {
        let registered = try await Self.registeredAccount(index: 0, lamports: 1_000_000)
        let shielded = try registered.keys.shieldedAccount(for: registered.account.address)
        let keys = StoredValue([registered.account.address.value: registered.keys])
        let id = PrivateBalances.noteID(of: registered.account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let lagging = HTTPResponses.privateNotes(deposits: [registered.deposit],
                                                 trees: UTXOTrees(rows: [registered.deposit], isFinalized: false))
        let spent = HTTPResponses.privateNotes(spends: [try PrivateBalanceFixtures.spend(of: 1_000_000, to: shielded, leafIndex: 1)],
                                               trees: UTXOTrees(rows: [registered.deposit]))

        let first = try await Self.balances(lagging, keys: keys, notes: notes).refresh(registered.account, on: .devnet)
        let later = try await Self.balances(spent, keys: keys, notes: notes).refresh(registered.account, on: .devnet)

        #expect(first == .balance(available: 0, pending: 0))
        #expect(later == .balance(available: 0, pending: 0))
        #expect(await notes.value?[id]?.notes.isEmpty == true)
        #expect(try await Self.methods(of: spent).contains(GetShieldedTransactionsByNullifiers.method))
    }

    @Test
    func `A completed deposit stays pending until its notes are included`() async throws {
        let registered = try await Self.registeredAccount(index: 0, lamports: 1_000_000)
        let keys = StoredValue([registered.account.address.value: registered.keys])
        let id = PrivateBalances.noteID(of: registered.account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let lagging = HTTPResponses.privateNotes(deposits: [registered.deposit],
                                                 trees: UTXOTrees(rows: [registered.deposit], isFinalized: false))
        let finalized = HTTPResponses.privateNotes(trees: UTXOTrees(rows: [registered.deposit]))
        let balances = try await Self.balances(lagging, keys: keys, notes: notes)
        let confirmation = PrivateBalanceFixtures.confirmation(.succeeded, signature: RedeemCodeFixtures.signature(ofDepositAt: 1))
        let completed = try await balances.complete(PrivateBalanceFixtures.preparedDeposit(1_000_000, from: registered.account),
                                                    with: confirmation)

        let reported = try await balances.refresh(registered.account, on: .devnet)
        let included = try await Self.balances(finalized, keys: keys, notes: notes).refresh(registered.account, on: .devnet)

        #expect(completed == .balance(available: 0, pending: 1_000_000))
        #expect(reported == .balance(available: 0, pending: 1_000_000))
        #expect(included == .balance(available: 1_000_000, pending: 0))
    }

    @Test
    func `An unregistered account reads no notes`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses([GetMultipleAccounts.method: [PrivateBalanceFixtures.unregistered]])
        let notes = StoredValue<PrivateBalances.Notes>()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        #expect(try await Self.balances(responses, keys: keys, notes: notes).refresh(account,
                                        on: .devnet) == .unregistered)
        #expect(await notes.value == nil)
        #expect(try await Self.methods(of: responses) == [GetMultipleAccounts.method])
    }

    @Test
    func `A refresh of an account registered with other keys fails`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let other = try PrivateBalanceFixtures.otherKeys(for: account.address)
        let responses = HTTPResponses([GetMultipleAccounts.method: [try PrivateBalanceFixtures.registry(publishing: other)]])
        let notes = StoredValue<PrivateBalances.Notes>()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        await #expect(throws: PrivateBalanceError.registeredWithOtherKeys) {
            try await Self.balances(responses, keys: keys, notes: notes).refresh(account, on: .devnet)
        }
        #expect(await notes.value == nil)
    }

    @Test(arguments: [false, true])
    func `A custom RPC off mainnet is unavailable`(hasNotes: Bool) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let saved: PrivateBalances.Notes? = hasNotes ? [PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()] : nil
        let notes = StoredValue(saved)
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        let status = try await Self.balances(responses, provider: try PrivateBalanceFixtures.customRPC(), keys: keys,
                                             notes: notes)
            .refresh(account, on: .devnet)

        #expect(status == .unavailable)
        #expect(await notes.value == saved)
        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `Provider errors fail the refresh and keep the saved notes`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes(error: .http(statusCode: 429, retryAfter: nil))
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            try await Self.balances(responses, keys: keys, notes: notes).refresh(account, on: .devnet)
        }
        #expect(await notes.value == [id: NoteSyncState()])
    }

    @Test
    func `The saved status holds the last synced balance without reading the network`() async throws {
        let registered = try await Self.registeredAccount(index: 0, lamports: 1_000_000)
        let responses = HTTPResponses.privateNotes(registry: [registered.registry], deposits: [registered.deposit])
        let keys = StoredValue([registered.account.address.value: registered.keys])
        let balances = try await Self.balances(responses, keys: keys)
        _ = try await balances.refresh(registered.account, on: .devnet)
        let syncRequests = await responses.requests.count

        let saved = try await balances.savedStatus(of: registered.account, on: .devnet)

        #expect(saved == .balance(available: 1_000_000, pending: 0))
        #expect(await responses.requests.count == syncRequests)
    }

    @Test
    func `Recorded notes need keys, and notes before the first sync have no saved status`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let recorded = try await PrivateBalanceFixtures.pendingDeposit(of: account).notes
        let responses = HTTPResponses.privateNotes()
        let withKeys = try await Self.balances(responses, keys: keys, notes: recorded)
        let keyless = try await Self.balances(responses, notes: recorded)
        let unsynced = try await Self.balances(responses, keys: keys, notes: StoredValue([id: NoteSyncState()]))

        async let saved = withKeys.savedStatus(of: account, on: .devnet)
        async let keylessStatus = keyless.savedStatus(of: account, on: .devnet)
        async let unsyncedStatus = unsynced.savedStatus(of: account, on: .devnet)

        #expect(try await saved == .balance(available: 0, pending: 1_000_000))
        #expect(try await keylessStatus == nil)
        #expect(try await unsyncedStatus == nil)
        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `Note IDs name the shielded-pool program`() async throws {
        let account = try await PrivateBalanceFixtures.account()

        #expect(PrivateBalances.noteID(of: account, on: .devnet).contains(ShieldedPool.programID))
    }

    @Test
    func `Concurrent refreshes of one account share one sync`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(
            deposits: [try PrivateBalanceFixtures.deposit(42, to: record.shieldedAccount(for: account.address), leafIndex: 1)],
            gate: gate, heldMethod: GetShieldedTransactionsByTags.method
        )
        let notes = StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        let balances = try await Self.balances(responses, keys: StoredValue([account.address.value: record]),
                                               notes: notes)

        let first = await Self.startRefresh(of: account, in: balances)
        await gate.waitUntilStarted()
        let second = await Self.startRefresh(of: account, in: balances)
        gate.resume()

        #expect(try await first.value == .balance(available: 42, pending: 0))
        #expect(try await second.value == .balance(available: 42, pending: 0))
        #expect(try await Self.methods(of: responses).filter { $0 == GetShieldedTransactionsByTags.method }.count == 1)
    }

    @Test
    func `A failed shared sync is retried by the next refresh`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let deposit = try PrivateBalanceFixtures.deposit(42, to: record.shieldedAccount(for: account.address), leafIndex: 1)
        let responses = HTTPResponses([
            GetShieldedTransactionsByTags.method: ["null", HTTPResponses.indexerPage([], in: "transactions")],
            GetEncryptedUtxosByTags.method: [HTTPResponses.indexerPage([deposit], in: "matches")],
            GetShieldedTransactionsByNullifiers.method: [HTTPResponses.indexerPage([], in: "transactions")],
        ], trees: UTXOTrees(rows: [deposit]))
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let balances = try await Self.balances(responses, keys: StoredValue([account.address.value: record]),
                                               notes: notes)

        await #expect(throws: RPCError.self) { try await balances.refresh(account, on: .devnet) }
        #expect(await notes.value == [id: NoteSyncState()])

        #expect(try await balances.refresh(account, on: .devnet) == .balance(available: 42, pending: 0))
        #expect(await notes.value?[id]?.lamports == 42)
        #expect(try await Self.methods(of: responses).filter { $0 == GetShieldedTransactionsByTags.method }.count == 2)
    }

    @Test
    func `A cancelled refresh fails while the shared sync still saves`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(
            deposits: [try PrivateBalanceFixtures.deposit(42, to: record.shieldedAccount(for: account.address), leafIndex: 1)],
            gate: gate, heldMethod: GetShieldedTransactionsByTags.method
        )
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let balances = try await Self.balances(responses, keys: StoredValue([account.address.value: record]),
                                               notes: notes)

        let refresh = await Self.startRefresh(of: account, in: balances)
        await gate.waitUntilStarted()
        refresh.cancel()
        gate.resume()

        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(await notes.value?[id]?.lamports == 42)
        #expect(!(await responses.wasCancelled))
    }

    @Test
    func `A reset during a sync leaves no notes`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(
            deposits: [try PrivateBalanceFixtures.deposit(42, to: record.shieldedAccount(for: account.address), leafIndex: 1)],
            gate: gate, heldMethod: GetShieldedTransactionsByTags.method
        )
        let keys = StoredValue([account.address.value: record])
        let notes = StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        let balances = try await Self.balances(responses, keys: keys, notes: notes)

        let refresh = await Self.startRefresh(of: account, in: balances)
        await gate.waitUntilStarted()
        try await balances.removeAll()
        gate.resume()

        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(await notes.value == nil)
        #expect(await keys.value == nil)
    }

    @Test
    func `Other accounts refresh while one account syncs`() async throws {
        async let derivedSyncing = PrivateBalanceFixtures.account(index: 0)
        async let derivedOther = PrivateBalanceFixtures.account(index: 1)
        let (syncing, other) = try await (derivedSyncing, derivedOther)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered], gate: gate,
                                                   heldMethod: GetShieldedTransactionsByTags.method)
        let keys = StoredValue([syncing.address.value: try await PrivateBalanceFixtures.keys(for: syncing),
                                other.address.value: try await PrivateBalanceFixtures.keys(for: other)])
        let notes = StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: syncing, on: .devnet): NoteSyncState()])
        let balances = try await Self.balances(responses, keys: keys, notes: notes)

        let sync = await Self.startRefresh(of: syncing, in: balances)
        await gate.waitUntilStarted()
        let otherStatus = try await balances.refresh(other, on: .devnet)
        gate.resume()

        #expect(otherStatus == .unregistered)
        #expect(try await sync.value == .balance(available: 0, pending: 0))
    }

    @Test
    func `An unreadable notes item is deleted and every account syncs from the start`() async throws {
        async let registeredFirst = Self.registeredAccount(index: 0, lamports: 1_000)
        async let registeredSecond = Self.registeredAccount(index: 1, lamports: 2_000)
        let (first, second) = try await (registeredFirst, registeredSecond)
        let responses = HTTPResponses.privateNotes(registry: [first.registry, second.registry],
                                                   deposits: [first.deposit, second.deposit])
        let firstID = PrivateBalances.noteID(of: first.account, on: .devnet)
        let secondID = PrivateBalances.noteID(of: second.account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([firstID: NoteSyncState(), secondID: NoteSyncState()],
                                                       unreadable: true)
        let keys = StoredValue([first.account.address.value: first.keys, second.account.address.value: second.keys])
        let balances = try await Self.balances(responses, keys: keys, notes: notes)

        let firstStatus = try await balances.refresh(first.account, on: .devnet)
        let secondStatus = try await balances.refresh(second.account, on: .devnet)

        #expect(firstStatus == .balance(available: 1_000, pending: 0))
        #expect(secondStatus == .balance(available: 2_000, pending: 0))
        #expect(await notes.deletions == 1)
        #expect(await notes.value?[firstID]?.lamports == 1_000)
        #expect(await notes.value?[secondID]?.lamports == 2_000)
        #expect(await PrivateBalanceFixtures.nonTreeAccountReads(of: responses) == 2)
        #expect(try await Self.tagCursors(of: responses) == [nil, nil])
    }

    @Test
    func `An unreadable keys item is deleted and private balances are off`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)],
                               unreadable: true)

        #expect(try await Self.balances(responses, keys: keys).refresh(account,
                                        on: .devnet) == .off(isRegistered: false))
        #expect(await keys.deletions == 1)
        #expect(await keys.value == nil)
        #expect(try await Self.methods(of: responses) == [GetMultipleAccounts.method])
    }

    @Test
    func `Enabling over an unreadable keys item deletes it and keeps the keys`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let keys = StoredValue<PrivateBalances.Keys>(unreadable: true)

        try await Self.balances(responses, keys: keys).enable(account, on: .devnet)

        #expect(await keys.deletions == 1)
        #expect(await keys.value == [account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
    }

    @Test
    func `An item unreadable again in the same launch fails the refresh without another deletion`() async throws {
        let registered = try await Self.registeredAccount(index: 0, lamports: 1_000)
        let responses = HTTPResponses.privateNotes(registry: [registered.registry], deposits: [registered.deposit])
        let keys = StoredValue([registered.account.address.value: registered.keys])
        let notes = StoredValue<PrivateBalances.Notes>(unreadable: true)
        let balances = try await Self.balances(responses, keys: keys, notes: notes)
        try #require(try await balances.refresh(registered.account, on: .devnet) == .balance(available: 1_000, pending: 0))
        let rebuilt = await notes.value

        await notes.makeUnreadable()

        await #expect(throws: KeychainItemError.unreadable) {
            try await balances.refresh(registered.account, on: .devnet)
        }
        #expect(await notes.deletions == 1)
        #expect(await notes.value == rebuilt)
    }

    @Test
    func `A reset during an unreadable read cancels the rebuild`() async throws {
        let registered = try await Self.registeredAccount(index: 0, lamports: 1_000)
        let responses = HTTPResponses.privateNotes(registry: [registered.registry], deposits: [registered.deposit])
        let gate = Suspension()
        let keys = StoredValue([registered.account.address.value: registered.keys])
        let notes = StoredValue<PrivateBalances.Notes>(unreadable: true, readGate: gate)
        let balances = try await Self.balances(responses, keys: keys, notes: notes)

        let held = await Self.startRefresh(of: registered.account, in: balances)
        await gate.waitUntilStarted()
        try await balances.removeAll()
        gate.resume()

        await #expect(throws: CancellationError.self) { try await held.value }
        #expect(await notes.deletions == 1)
        #expect(await notes.value == nil)
        #expect(await keys.value == nil)
    }

    @Test
    func `A failed deletion is tried again by the next refresh`() async throws {
        let registered = try await Self.registeredAccount(index: 0, lamports: 1_000)
        let responses = HTTPResponses.privateNotes(registry: [registered.registry], deposits: [registered.deposit])
        let keys = StoredValue([registered.account.address.value: registered.keys])
        let notes = StoredValue<PrivateBalances.Notes>(failsFirstDeletion: true, unreadable: true)
        let balances = try await Self.balances(responses, keys: keys, notes: notes)

        await #expect(throws: CocoaError.self) { try await balances.refresh(registered.account, on: .devnet) }
        let retried = try await balances.refresh(registered.account, on: .devnet)

        #expect(retried == .balance(available: 1_000, pending: 0))
        #expect(await notes.deletions == 1)
    }

    @Test
    func `Concurrent refreshes that read an unreadable item delete it once`() async throws {
        async let registeredFirst = Self.registeredAccount(index: 0, lamports: 1_000)
        async let registeredSecond = Self.registeredAccount(index: 1, lamports: 2_000)
        let (first, second) = try await (registeredFirst, registeredSecond)
        let responses = HTTPResponses.privateNotes(registry: [second.registry, first.registry],
                                                   deposits: [first.deposit, second.deposit])
        let gate = Suspension()
        let notes = StoredValue<PrivateBalances.Notes>(
            [PrivateBalances.noteID(of: first.account, on: .devnet): NoteSyncState(),
             PrivateBalances.noteID(of: second.account, on: .devnet): NoteSyncState()],
            unreadable: true, readGate: gate
        )
        let keys = StoredValue([first.account.address.value: first.keys, second.account.address.value: second.keys])
        let balances = try await Self.balances(responses, keys: keys, notes: notes)

        let held = await Self.startRefresh(of: first.account, in: balances)
        await gate.waitUntilStarted()
        let secondStatus = try await balances.refresh(second.account, on: .devnet)
        gate.resume()

        #expect(secondStatus == .balance(available: 2_000, pending: 0))
        #expect(try await held.value == .balance(available: 1_000, pending: 0))
        #expect(await notes.deletions == 1)
    }

    @Test
    func `Preparing a registered account's deposit deposits into its own balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try record.shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(outputTreeID: 1)
        let notes = StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        let balances = try await Self.balances(responses, keys: StoredValue([account.address.value: record]),
                                               notes: notes)

        let prepared = try await balances.prepare(.deposit(5_000), from: account, on: .devnet)

        #expect(prepared.instructions == [try ShieldedPool.deposit(lamports: 5_000, from: account.address, to: shielded.recipient,
                                                                   treeID: 1)])
        #expect(!prepared.registers)
        #expect(prepared.network == .devnet)
        #expect(try await !Self.methods(of: responses).contains(GetMultipleAccounts.method))
    }

    @Test
    func `Preparing an unregistered account's first deposit registers it without saving notes`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try record.shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered], outputTreeID: 1)
        let notes = StoredValue<PrivateBalances.Notes>()
        let balances = try await Self.balances(responses, keys: StoredValue([account.address.value: record]),
                                               notes: notes)

        let prepared = try await balances.prepare(.deposit(5_000), from: account, on: .devnet)

        #expect(prepared.instructions == [
            try shielded.register(paidBy: account.address),
            try ShieldedPool.deposit(lamports: 5_000, from: account.address, to: shielded.recipient, treeID: 1),
        ])
        #expect(prepared.registers)
        #expect(await notes.value == nil)
    }

    @Test
    func `Preparing a deposit without an output tree is unavailable`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let notes = StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        await #expect(throws: PrivateBalanceError.unavailable) {
            try await Self.balances(responses, keys: keys, notes: notes).prepare(.deposit(5_000), from: account,
                                    on: .devnet)
        }
    }

    @Test
    func `Preparing a withdrawal without an output tree is unavailable`() async throws {
        let sender = try await Self.fundedAccount(lamports: 1_000_000)
        let responses = HTTPResponses.privateNotes(deposits: [sender.deposit], prover: try IndexedProofs.prover())

        await #expect(throws: PrivateBalanceError.unavailable) {
            try await Self.balances(responses, keys: sender.keys, notes: sender.notes)
                .prepare(.withdraw(400_000, to: sender.account.address), from: sender.account, on: .devnet)
        }
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 0)
    }

    @Test
    func `Preparing a send with a custom RPC off mainnet is unavailable`() async throws {
        async let funded = Self.fundedAccount(lamports: 1_000_000)
        async let derivedRecipient = PrivateBalanceFixtures.account(index: 1)
        let (sender, recipient) = try await (funded, derivedRecipient)

        await #expect(throws: PrivateBalanceError.unavailable) {
            try await Self.balances(HTTPResponses.privateNotes(), provider: try PrivateBalanceFixtures.customRPC(),
                                    keys: sender.keys, notes: sender.notes)
                .prepare(.send(400_000, to: recipient.address), from: sender.account, on: .devnet)
        }
    }

    @Test
    func `Preparing without keys is turned off`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let balances = try await Self.balances(HTTPResponses.privateNotes(outputTreeID: 1),
                                               notes: StoredValue([id: NoteSyncState()]))

        await #expect(throws: PrivateBalanceError.turnedOff) {
            try await balances.prepare(.deposit(5_000), from: account, on: .devnet)
        }
    }

    @Test
    func `Preparing a send to an unregistered recipient offers a regular payment`() async throws {
        async let funded = Self.fundedAccount(lamports: 1_000_000)
        async let derivedRecipient = PrivateBalanceFixtures.account(index: 1)
        let (sender, recipient) = try await (funded, derivedRecipient)
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered], deposits: [sender.deposit],
                                                   outputTreeID: 1, prover: try IndexedProofs.prover())

        await #expect(throws: PrivateBalanceError.recipientUnregistered) {
            try await Self.balances(responses, keys: sender.keys, notes: sender.notes)
                .prepare(.send(400_000, to: recipient.address), from: sender.account, on: .devnet)
        }
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 0)
    }

    @Test(arguments: [ProviderSettings.Provider.helius, .solana])
    func `Preparing a send proves a private transfer`(provider: ProviderSettings.Provider) async throws {
        async let funded = Self.fundedAccount(lamports: 1_000_000)
        async let derivedRecipient = PrivateBalanceFixtures.account(index: 1)
        let (sender, recipient) = try await (funded, derivedRecipient)
        let recipientKeys = try await PrivateBalanceFixtures.keys(for: recipient)
        let registry = try PrivateBalanceFixtures.registry(publishing: recipientKeys.shieldedAccount(for: recipient.address))
        let responses = HTTPResponses.privateNotes(registry: [registry, PrivateBalanceFixtures.unregistered],
                                                   deposits: [sender.deposit], outputTreeID: 1,
                                                   prover: try IndexedProofs.prover())
        let balances = try await Self.balances(responses, provider: provider, keys: sender.keys, notes: sender.notes)

        let prepared = try await balances.prepare(.send(400_000, to: recipient.address), from: sender.account, on: .devnet)

        guard case .spend(let spend) = prepared.effect else {
            Issue.record("Expected a spend.")
            return
        }
        #expect(prepared.instructions == [spend.instruction])
        #expect(spend.lamports == 400_000)
        #expect(spend.receivedLamports == 600_000)
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 1)
        #expect(try await balances.complete(prepared, with: PrivateBalanceFixtures.confirmation(.succeeded)) == .balance(available: 0, pending: 600_000))
        #expect(await sender.notes.value?[sender.id]?.notes.isEmpty == true)
    }

    @Test
    func `Preparing a withdrawal proves a public withdrawal`() async throws {
        async let funded = Self.fundedAccount(lamports: 1_000_000)
        async let derivedDestination = PrivateBalanceFixtures.account(index: 1)
        let (sender, destination) = try await (funded, derivedDestination)
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered], deposits: [sender.deposit],
                                                   outputTreeID: 1,
                                                   prover: try IndexedProofs.prover())

        let prepared = try await Self.balances(responses, keys: sender.keys, notes: sender.notes)
            .prepare(.withdraw(1_000_000, to: destination.address), from: sender.account, on: .devnet)

        guard case .spend(let spend) = prepared.effect else {
            Issue.record("Expected a spend.")
            return
        }
        #expect(spend.lamports == 1_000_000)
        #expect(spend.receivedLamports == 0)
        #expect(spend.instruction.accounts.last?.address == destination.address)
    }

    @Test(arguments: [true, false])
    func `Spends beyond the spendable notes are insufficient`(isRegistered: Bool) async throws {
        let sender = try await Self.fundedAccount(lamports: 1_000_000)
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered],
                                                   deposits: isRegistered ? [sender.deposit] : [], outputTreeID: 1,
                                                   prover: try IndexedProofs.prover())
        let notes = isRegistered ? sender.notes : StoredValue<PrivateBalances.Notes>()

        await #expect(throws: PrivateBalanceError.insufficientBalance) {
            try await Self.balances(responses, keys: sender.keys, notes: notes)
                .prepare(.withdraw(2_000_000, to: sender.account.address), from: sender.account, on: .devnet)
        }
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 0)
    }

    @Test
    func `Completing a succeeded deposit keeps it pending`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let balances = try await Self.balances(HTTPResponses.privateNotes(), notes: notes)

        let status = try await balances.complete(PrivateBalanceFixtures.preparedDeposit(5_000, from: account), with: PrivateBalanceFixtures.confirmation(.succeeded))

        #expect(status == .balance(available: 0, pending: 5_000))
        #expect(await notes.value?[id]?.pendingLamports == 5_000)
    }

    @Test
    func `Completing a first deposit creates the notes entry`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered], outputTreeID: 1)
        let notes = StoredValue<PrivateBalances.Notes>()
        let balances = try await Self.balances(responses, keys: StoredValue([account.address.value: record]),
                                               notes: notes)
        let prepared = try await balances.prepare(.deposit(5_000), from: account, on: .devnet)

        let status = try await balances.complete(prepared, with: PrivateBalanceFixtures.confirmation(.succeeded))

        #expect(status == .balance(available: 0, pending: 5_000))
        #expect(await notes.value?[PrivateBalances.noteID(of: account, on: .devnet)]?.pendingLamports == 5_000)
    }

    @Test(arguments: [widgets.Confirmation.Outcome.failed(TransactionError(name: "InsufficientFundsForFee", details: nil)), .dropped])
    func `Failed or dropped transactions change nothing`(outcome: widgets.Confirmation.Outcome) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let balances = try await Self.balances(HTTPResponses.privateNotes(), keys: keys, notes: notes)

        let status = try await balances.complete(PrivateBalanceFixtures.preparedDeposit(5_000, from: account), with: PrivateBalanceFixtures.confirmation(outcome))

        #expect(status == .balance(available: 0, pending: 0))
        #expect(await notes.value == [id: NoteSyncState()])
    }

    @Test
    func `Completing with another network's confirmation is rejected`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let confirmation = widgets.Confirmation(submission: Submission(signature: "mainnet", network: .mainnet, lastValidBlockHeight: 1),
                                        slot: 5, outcome: .succeeded)

        await #expect(throws: Transactions.ValidationError.invalidTransaction) {
            try await Self.balances(HTTPResponses.privateNotes(), notes: notes)
                .complete(PrivateBalanceFixtures.preparedDeposit(5_000, from: account), with: confirmation)
        }
        #expect(await notes.value == [id: NoteSyncState()])
    }

    @Test
    func `Completing waits for a running sync`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(gate: gate, heldMethod: GetShieldedTransactionsByTags.method)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let balances = try await Self.balances(responses, keys: keys, notes: notes)

        let refresh = await Self.startRefresh(of: account, in: balances)
        await gate.waitUntilStarted()
        let completion = await Self.startCompletion(of: PrivateBalanceFixtures.preparedDeposit(5_000, from: account), in: balances)
        gate.resume()

        #expect(try await refresh.value == .balance(available: 0, pending: 0))
        #expect(try await completion.value == .balance(available: 0, pending: 5_000))
        #expect(await notes.value?[id]?.pendingLamports == 5_000)
    }

    @Test
    func `A sync waits for a running completion`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let gate = Suspension()
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()], gate: gate)
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let balances = try await Self.balances(HTTPResponses.privateNotes(), keys: keys, notes: notes)

        let completion = await Self.startCompletion(of: PrivateBalanceFixtures.preparedDeposit(5_000, from: account), in: balances)
        await gate.waitUntilStarted()
        let refresh = await Self.startRefresh(of: account, in: balances)
        gate.resume()

        #expect(try await completion.value == .balance(available: 0, pending: 5_000))
        #expect(try await refresh.value == .balance(available: 0, pending: 5_000))
        #expect(await notes.value?[id]?.pendingLamports == 5_000)
    }

    @Test(arguments: [widgets.Confirmation.Outcome.succeeded, .dropped])
    func `A reset during a completion cancels it`(outcome: widgets.Confirmation.Outcome) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(gate: gate, heldMethod: GetShieldedTransactionsByTags.method)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let balances = try await Self.balances(responses, keys: keys, notes: notes)

        let refresh = await Self.startRefresh(of: account, in: balances)
        await gate.waitUntilStarted()
        let completion = await Self.startCompletion(of: PrivateBalanceFixtures.preparedDeposit(5_000, from: account), outcome: outcome, in: balances)
        try await balances.removeAll()
        gate.resume()

        await #expect(throws: CancellationError.self) { try await refresh.value }
        await #expect(throws: CancellationError.self) { try await completion.value }
        #expect(await notes.value == nil)
    }

    @Test
    func `Overlapping completions run one at a time`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let gate = Suspension()
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()], gate: gate)
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let balances = try await Self.balances(HTTPResponses.privateNotes(), keys: keys, notes: notes)

        let first = await Self.startCompletion(of: PrivateBalanceFixtures.preparedDeposit(5_000, from: account), signature: "first", in: balances)
        await gate.waitUntilStarted()
        let second = await Self.startCompletion(of: PrivateBalanceFixtures.preparedDeposit(7_000, from: account), signature: "second", in: balances)
        let refresh = await Self.startRefresh(of: account, in: balances)
        gate.resume()

        #expect(try await first.value == .balance(available: 0, pending: 5_000))
        #expect(try await second.value == .balance(available: 0, pending: 12_000))
        #expect(try await refresh.value == .balance(available: 0, pending: 12_000))
        #expect(await notes.value?[id]?.pendingLamports == 12_000)
    }

    @Test
    func `Preparing a spend of too many notes is rejected`() async throws {
        let sender = try await Self.fundedAccount(lamports: 1)
        let shielded = try await PrivateBalanceFixtures.keys(for: sender.account).shieldedAccount(for: sender.account.address)
        let deposits = try (1...41).map { try PrivateBalanceFixtures.deposit(1, to: shielded, leafIndex: UInt64($0)) }
        let responses = HTTPResponses.privateNotes(deposits: deposits, outputTreeID: 1,
                                                   prover: try IndexedProofs.prover())

        await #expect(throws: PrivateBalanceError.tooManyNotes) {
            try await Self.balances(responses, keys: sender.keys, notes: sender.notes)
                .prepare(.withdraw(41, to: sender.account.address), from: sender.account, on: .devnet)
        }
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 0)
    }

    @Test
    func `Preparing for an account registered with other keys fails`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let other = try PrivateBalanceFixtures.otherKeys(for: account.address)
        let responses = HTTPResponses.privateNotes(registry: [try PrivateBalanceFixtures.registry(publishing: other)], outputTreeID: 1)
        let notes = StoredValue<PrivateBalances.Notes>()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        await #expect(throws: PrivateBalanceError.registeredWithOtherKeys) {
            try await Self.balances(responses, keys: keys, notes: notes).prepare(.deposit(5_000), from: account,
                                    on: .devnet)
        }
        #expect(await notes.value == nil)
    }

    @Test
    func `Preparing for a registered account without notes saves its entry`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try record.shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(registry: [try PrivateBalanceFixtures.registry(publishing: shielded)], outputTreeID: 1)
        let notes = StoredValue<PrivateBalances.Notes>()
        let balances = try await Self.balances(responses, keys: StoredValue([account.address.value: record]),
                                               notes: notes)

        let prepared = try await balances.prepare(.deposit(5_000), from: account, on: .devnet)

        #expect(prepared.instructions == [try ShieldedPool.deposit(lamports: 5_000, from: account.address, to: shielded.recipient,
                                                                   treeID: 1)])
        #expect(!prepared.registers)
        #expect(await notes.value?[PrivateBalances.noteID(of: account, on: .devnet)] != nil)
    }

    @MainActor
    private static func balances(
        _ responses: HTTPResponses, provider: ProviderSettings.Provider = .helius,
        recovery: SecurityRecoveryStore? = nil, keys: StoredValue<PrivateBalances.Keys> = StoredValue(),
        notes: StoredValue<PrivateBalances.Notes> = StoredValue()
    ) throws -> PrivateBalances {
        PrivateBalances.inMemory(keys: keys, notes: notes,
                                 recovery: try recovery ?? PrivateBalanceFixtures.recoveryStore(), responses: responses,
                                 provider: provider)
    }

    private static func registeredAccount(index: UInt32, lamports: UInt64) async throws
        -> (account: widgets.Account, keys: PrivateBalanceKeyRecord, registry: String, deposit: String) {
        let account = try await PrivateBalanceFixtures.account(index: index)
        let keys = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try keys.shieldedAccount(for: account.address)
        return (account, keys, try PrivateBalanceFixtures.registry(publishing: shielded),
                try PrivateBalanceFixtures.deposit(lamports, to: shielded, leafIndex: UInt64(index) + 1))
    }

    private static func fundedAccount(lamports: UInt64) async throws -> (account: widgets.Account,
        keys: StoredValue<PrivateBalances.Keys>, notes: StoredValue<PrivateBalances.Notes>, id: String, deposit: String) {
        let registered = try await registeredAccount(index: 0, lamports: lamports)
        let id = PrivateBalances.noteID(of: registered.account, on: .devnet)
        return (registered.account, StoredValue([registered.account.address.value: registered.keys]),
                StoredValue([id: NoteSyncState()]), id, registered.deposit)
    }

    private static func tagCursors(of responses: HTTPResponses) async throws -> [String?] {
        try await responses.requests.filter { try $0.rpcMethod == GetShieldedTransactionsByTags.method }
            .map { try #require($0.jsonBody()["params"] as? [String: Any])["cursor"] as? String }
    }

    private static func methods(of responses: HTTPResponses) async throws -> [String] {
        try await responses.requests.map { try $0.rpcMethod }
    }

    private static func startCompletion(of transaction: PreparedPrivateTransaction, signature: String = "private",
                                        outcome: widgets.Confirmation.Outcome = .succeeded,
                                        in balances: isolated PrivateBalances) -> Task<PrivateBalanceStatus, any Error> {
        Task.immediate { try await balances.complete(transaction, with: PrivateBalanceFixtures.confirmation(outcome, signature: signature)) }
    }

    private static func startRefresh(of account: widgets.Account,
                                     in balances: isolated PrivateBalances) -> Task<PrivateBalanceStatus, any Error> {
        Task.immediate { try await balances.refresh(account, on: .devnet) }
    }
}
