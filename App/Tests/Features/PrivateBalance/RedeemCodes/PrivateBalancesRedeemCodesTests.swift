import CryptoKit
import Foundation
import Privacy
@testable import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Verifies creating, redeeming, taking back, and listing redeem codes through the real provider client with local
/// accounts, indexer, and prover responses, in in-memory storage.
@Suite(.timeLimit(.minutes(1)))
struct PrivateBalancesRedeemCodesTests {
    /// The lamports that the sender's only note holds.
    private static let senderLamports: UInt64 = 5_000_000

    /// A new code takes the first index above the one that the chain shows used, keeps it pending before the
    /// preparation returns, and spends its amount and its reserve to that one-time account; its success turns the
    /// pending index into the code.
    @Test
    func `Creating a code funds the next unused one-time account`() async throws {
        let sender = try await Self.sender()
        let used = try sender.keys.oneTimeAccount(at: 0)
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [
            sender.deposit, try RedeemCodeFixtures.deposit(1, to: used, leafIndex: 9),
        ])
        let codes = StoredValue<PrivateBalances.Codes>()
        let balances = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        let prepared = try await balances.prepare(.createCode(1_000_000), from: sender.account, on: .devnet)

        guard case .createCode(let spend, let index, let reserve) = prepared.effect else {
            Issue.record("Expected a code's creation.")
            return
        }
        #expect(index == 1)
        #expect(reserve == RedeemCodeFixtures.reserve)
        #expect(spend.lamports == 1_000_000)
        #expect(spend.receivedLamports == Self.senderLamports - 1_000_000 - reserve)
        #expect(spend.instruction.accounts.last?.address.value == (try sender.keys.oneTimeAccount(at: 1)).address)
        #expect(try prepared.authorities.map { try $0.address } == [sender.account.address])
        #expect(prepared.instructions == [spend.instruction])
        #expect(await codes.value?[sender.id]?.pending.map(\.index) == [1])
        #expect(await codes.value?[sender.id]?.nextIndex == 2)

        _ = try await balances.complete(prepared, with: PrivateBalanceFixtures.confirmation(.succeeded, signature: "funding"))

        let ledger = try #require(await codes.value?[sender.id])
        #expect(ledger.pending.isEmpty)
        #expect(ledger.records.map(\.index) == [1])
        #expect(ledger.records.first?.amount == 1_000_000)
        #expect(ledger.records.first?.reserve == reserve)
        #expect(ledger.records.first?.fundingSignature == "funding")
        #expect(ledger.nextIndex == 2)
        #expect(!ledger.isDiscovered)
    }

    /// Two codes prepared at once take different indices, and a dropped code leaves the pending indices without its
    /// index being used again.
    @Test
    func `Concurrent codes take different indices and a dropped code's index isn't reused`() async throws {
        let sender = try await Self.sender()
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [sender.deposit])
        let codes = StoredValue<PrivateBalances.Codes>()
        let balances = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        async let preparedFirst = balances.prepare(.createCode(1_000), from: sender.account, on: .devnet)
        async let preparedSecond = balances.prepare(.createCode(2_000), from: sender.account, on: .devnet)
        let (first, second) = try await (preparedFirst, preparedSecond)
        try #require(Set([first, second].compactMap(Self.index(of:))) == [0, 1])
        let dropped = Self.index(of: first) == 0 ? first : second
        _ = try await balances.complete(dropped, with: PrivateBalanceFixtures.confirmation(.dropped))
        let third = try await balances.prepare(.createCode(3_000), from: sender.account, on: .devnet)

        #expect(Self.index(of: third) == 2)
        #expect(await codes.value?[sender.id]?.pending.map(\.index) == [1, 2])
        #expect(await codes.value?[sender.id]?.records.isEmpty == true)
    }

    /// An app that quits after submitting a code's funding and before recording its outcome must not
    /// give a later code the same index while the indexer doesn't report the funding yet; the index stays pending in
    /// storage, so a relaunch starts above it.
    @Test
    func `A relaunch after an unrecorded funding doesn't reuse its index`() async throws {
        let sender = try await Self.sender()
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [sender.deposit])
        let codes = StoredValue<PrivateBalances.Codes>()

        let first = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)
            .prepare(.createCode(1_000), from: sender.account, on: .devnet)
        let relaunched = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)
        let second = try await relaunched.prepare(.createCode(1_000), from: sender.account, on: .devnet)

        #expect(Self.index(of: first) == 0)
        #expect(Self.index(of: second) == 1)
    }

    /// A new code's index choice reads only 20 tags from the next index; the entry's pending indices already keep the
    /// indices of this device's unrecorded codes.
    @Test
    func `A new code's index choice reads 20 tags`() async throws {
        let sender = try await Self.sender()
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [sender.deposit])
        let codes = StoredValue([sender.id: RedeemCodeLedger(nextIndex: 40, isDiscovered: true)])

        let prepared = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)
            .prepare(.createCode(1_000), from: sender.account, on: .devnet)

        #expect(Self.index(of: prepared) == 40)
        #expect(try await RedeemCodeFixtures.tagCounts(of: responses).contains(RedeemCodeScan.choiceBatchSize))
        #expect(try await !RedeemCodeFixtures.tagCounts(of: responses).contains(RedeemCodeScan.discoveryBatchSize))
    }

    /// If saving a succeeded code's record fails, its index stays pending, so a later listing still
    /// finds the code's note instead of losing the code.
    @Test
    func `A failed record save keeps the code's index pending`() async throws {
        let sender = try await Self.sender()
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [sender.deposit])
        let codes = StoredValue<PrivateBalances.Codes>()
        let balances = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)
        let prepared = try await balances.prepare(.createCode(1_000), from: sender.account, on: .devnet)
        await codes.failSaving()

        await #expect(throws: CocoaError.self) {
            try await balances.complete(prepared, with: PrivateBalanceFixtures.confirmation(.succeeded, signature: "funding"))
        }
        #expect(await codes.value?[sender.id]?.pending.map(\.index) == [0])
    }

    /// Without keys, an account can't create codes: no index is chosen and nothing is proved.
    @Test
    func `Creating a code without keys is turned off`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [])
        let codes = StoredValue<PrivateBalances.Codes>()

        await #expect(throws: PrivateBalanceError.turnedOff) {
            try await Self.balances(responses, codes: codes).prepare(.createCode(1_000), from: account, on: .devnet)
        }
        #expect(await codes.value == nil)
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 0)
    }

    /// A redeem into a registered account spends the code's note to it and deposits every other lamport, which the
    /// one-time account alone signs and pays for; its success keeps both amounts pending.
    @Test
    func `Redeeming into a registered account sweeps the code`() async throws {
        let recipient = try await Self.recipient(registered: true)
        let oneTime = try Self.giftedAccount()
        let responses = try RedeemCodeFixtures.responses(accounts: [
            oneTime.address: RedeemCodeFixtures.systemAccount(lamports: RedeemCodeFixtures.reserve),
            try RedeemCodeFixtures.recordAddress(of: recipient.account): recipient.record,
        ], deposits: [try RedeemCodeFixtures.deposit(1_000_000, to: oneTime, leafIndex: 3)])
        let balances = try Self.balances(responses, keys: recipient.storedKeys, notes: recipient.notes)
        let code = try RedeemCode(secret: oneTime.secret, network: .devnet)

        let prepared = try await balances.prepare(.redeem(code), from: recipient.account, on: .devnet)

        guard case .redeem(let redemption) = prepared.effect else {
            Issue.record("Expected a redemption.")
            return
        }
        // One input slot pays the tree fee once, as the reserve expects.
        #expect(redemption.availableLamports == RedeemCodeFixtures.reserve - RedeemCodeFixtures.treeFee)
        #expect(redemption.noteLamports == 1_000_000)
        #expect(redemption.takenBackIndex == nil)
        #expect(!prepared.registers)
        #expect(try prepared.authorities.map { try $0.address } == [Address(oneTime.address)])
        #expect(prepared.instructions.count == 2)
        #expect(prepared.instructions.last == (try ShieldedPool.deposit(
            lamports: redemption.availableLamports, from: Address(oneTime.address),
            to: recipient.shielded.recipient, treeID: 1
        )))

        let charged = try prepared.withNetworkFee(5_000)
        let status = try await balances.complete(charged, with: PrivateBalanceFixtures.confirmation(.succeeded))

        let deposited = 1_000_000 + RedeemCodeFixtures.reserve - RedeemCodeFixtures.treeFee - 5_000
        #expect(status == .lamports(deposited))
        #expect(await recipient.notes.value?[recipient.id]?.pendingLamports == deposited)
    }

    /// A redeem into an unregistered account registers it first, paid by the one-time account, and both sign; a
    /// reserve-sized balance leaves no deposit once the two signatures are charged.
    @Test
    func `Redeeming into an unregistered account registers it`() async throws {
        let recipient = try await Self.recipient(registered: false)
        let oneTime = try Self.giftedAccount()
        let responses = try RedeemCodeFixtures.responses(accounts: [
            oneTime.address: RedeemCodeFixtures.systemAccount(lamports: RedeemCodeFixtures.reserve),
        ], deposits: [try RedeemCodeFixtures.deposit(1_000_000, to: oneTime, leafIndex: 3)])
        let balances = try Self.balances(responses, keys: recipient.storedKeys, notes: recipient.notes)

        let prepared = try await balances.prepare(.redeem(RedeemCode(secret: oneTime.secret, network: .devnet)),
                                                  from: recipient.account, on: .devnet)
        let charged = try prepared.withNetworkFee(2 * Redemption.signatureFee)

        #expect(prepared.registers)
        #expect(try prepared.authorities.map { try $0.address } == [Address(oneTime.address), recipient.account.address])
        #expect(prepared.instructions.first == (try recipient.shielded.register(paidBy: Address(oneTime.address))))
        #expect(prepared.instructions.count == 3)
        #expect(charged.instructions == Array(prepared.instructions.prefix(2)))
        #expect(try await balances.complete(charged, with: PrivateBalanceFixtures.confirmation(.succeeded)) == .lamports(1_000_000))
        #expect(await recipient.notes.value?[recipient.id]?.pendingLamports == 1_000_000)
    }

    /// A code whose one-time account holds no lamports was redeemed or taken back, and nothing is proved.
    @Test
    func `Redeeming a swept code is rejected`() async throws {
        let recipient = try await Self.recipient(registered: true)
        let oneTime = try Self.giftedAccount()
        let responses = try RedeemCodeFixtures.responses(accounts: [
            try RedeemCodeFixtures.recordAddress(of: recipient.account): recipient.record,
        ], deposits: [try RedeemCodeFixtures.deposit(1_000_000, to: oneTime, leafIndex: 3)])

        await #expect(throws: PrivateBalanceError.codeRedeemed) {
            try await Self.balances(responses, keys: recipient.storedKeys, notes: recipient.notes)
                .prepare(.redeem(RedeemCode(secret: oneTime.secret, network: .devnet)), from: recipient.account,
                         on: .devnet)
        }
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 0)
    }

    /// A code whose one-time account holds lamports but whose note the indexer doesn't report yet isn't ready, so no
    /// sweep leaves the note behind.
    @Test
    func `Redeeming a code before its note is indexed is rejected`() async throws {
        let recipient = try await Self.recipient(registered: true)
        let oneTime = try Self.giftedAccount()
        let responses = try RedeemCodeFixtures.responses(accounts: [
            oneTime.address: RedeemCodeFixtures.systemAccount(lamports: RedeemCodeFixtures.reserve),
            try RedeemCodeFixtures.recordAddress(of: recipient.account): recipient.record,
        ], deposits: [])

        await #expect(throws: PrivateBalanceError.codeNotReady) {
            try await Self.balances(responses, keys: recipient.storedKeys, notes: recipient.notes)
                .prepare(.redeem(RedeemCode(secret: oneTime.secret, network: .devnet)), from: recipient.account,
                         on: .devnet)
        }
    }

    /// A one-time account whose lamports don't cover the registration and the tree fee is underfunded.
    @Test
    func `Redeeming an underfunded code is rejected`() async throws {
        let recipient = try await Self.recipient(registered: false)
        let oneTime = try Self.giftedAccount()
        let responses = try RedeemCodeFixtures.responses(accounts: [
            oneTime.address: RedeemCodeFixtures.systemAccount(lamports: RedeemCodeFixtures.rent),
        ], deposits: [try RedeemCodeFixtures.deposit(1_000_000, to: oneTime, leafIndex: 3)])

        await #expect(throws: PrivateBalanceError.codeUnderfunded) {
            try await Self.balances(responses, keys: recipient.storedKeys, notes: recipient.notes)
                .prepare(.redeem(RedeemCode(secret: oneTime.secret, network: .devnet)), from: recipient.account,
                         on: .devnet)
        }
    }

    /// A code for another network is rejected before any request.
    @Test
    func `Redeeming another network's code is rejected`() async throws {
        let recipient = try await Self.recipient(registered: true)
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [])

        await #expect(throws: PrivateBalanceError.codeForOtherNetwork) {
            try await Self.balances(responses, keys: recipient.storedKeys, notes: recipient.notes)
                .prepare(.redeem(RedeemCode(secret: Self.giftedAccount().secret, network: .mainnet)),
                         from: recipient.account, on: .devnet)
        }
        #expect(await responses.requests.isEmpty)
    }

    /// Taking back one of the account's own codes sweeps it into the account's private balance and drops the code.
    @Test
    func `Taking back a code sweeps it home and drops it`() async throws {
        let sender = try await Self.sender()
        let oneTime = try sender.keys.oneTimeAccount(at: 1)
        let responses = try RedeemCodeFixtures.responses(accounts: [
            oneTime.address: RedeemCodeFixtures.systemAccount(lamports: RedeemCodeFixtures.reserve),
            try RedeemCodeFixtures.recordAddress(of: sender.account): sender.record,
        ], deposits: [sender.deposit, try RedeemCodeFixtures.deposit(1_000, to: oneTime, leafIndex: 3)])
        let codes = StoredValue([sender.id: RedeemCodeLedger(records: [Self.record(at: 0), Self.record(at: 1)],
                                                             isDiscovered: true)])
        let balances = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        let prepared = try await balances.prepare(.takeBack(index: 1), from: sender.account, on: .devnet)
        guard case .redeem(let redemption) = prepared.effect else {
            Issue.record("Expected a redemption.")
            return
        }
        let charged = try prepared.withNetworkFee(5_000)
        _ = try await balances.complete(charged, with: PrivateBalanceFixtures.confirmation(.succeeded))

        #expect(redemption.takenBackIndex == 1)
        // The take-back reads the keys once, and the shared sync once.
        #expect(await sender.storedKeys.loads == 2)
        #expect(try prepared.authorities.map { try $0.address } == [Address(oneTime.address)])
        #expect(await codes.value?[sender.id]?.records.map(\.index) == [0])
        #expect(await codes.value?[sender.id]?.nextIndex == 2)
        #expect(await sender.notes.value?[sender.id]?.pendingLamports == 1_000 + RedeemCodeFixtures.reserve
            - RedeemCodeFixtures.treeFee - 5_000)
    }

    /// A code's status comes from the indexer, not from public lamports. A lagging node that reports
    /// no one-time account doesn't drop a code with unspent notes or one whose funding isn't indexed yet, and only a
    /// code whose notes are all spent leaves; no account is read.
    @Test
    func `Outstanding codes follow the indexer, not a lagging node`() async throws {
        let sender = try await Self.sender()
        let held = try sender.keys.oneTimeAccount(at: 0)
        let swept = try sender.keys.oneTimeAccount(at: 2)
        let responses = try RedeemCodeFixtures.responses(
            accounts: [:],
            deposits: [try RedeemCodeFixtures.deposit(700, to: held, leafIndex: 3),
                       try RedeemCodeFixtures.deposit(500, to: swept, leafIndex: 4)],
            spends: [try RedeemCodeFixtures.spend(of: 500, to: swept, leafIndex: 4)]
        )
        let codes = StoredValue([sender.id: RedeemCodeLedger(records: [Self.record(at: 0), Self.record(at: 1),
                                                                       Self.record(at: 2)], isDiscovered: true)])
        let balances = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        let outstanding = try await balances.outstandingCodes(of: sender.account, on: .devnet)

        let expected = [Self.record(at: 0, amount: 700), Self.record(at: 1)]
        #expect(outstanding.map(\.record) == expected)
        #expect(outstanding.map(\.code) == [try RedeemCode(secret: held.secret, network: .devnet),
                                            try RedeemCode(secret: sender.keys.oneTimeAccount(at: 1).secret,
                                                           network: .devnet)])
        #expect(await codes.value?[sender.id]?.records == expected)
        #expect(try await !Self.methods(of: responses).contains(GetMultipleAccounts.method))
    }

    /// Public lamports left on a one-time account whose notes are all spent, such as dust sent after
    /// a sweep, don't keep the code outstanding.
    @Test
    func `Leftover lamports don't keep a spent code`() async throws {
        let sender = try await Self.sender()
        let swept = try sender.keys.oneTimeAccount(at: 1)
        let responses = try RedeemCodeFixtures.responses(
            accounts: [swept.address: RedeemCodeFixtures.systemAccount(lamports: 5_000)],
            deposits: [try RedeemCodeFixtures.deposit(500, to: swept, leafIndex: 4)],
            spends: [try RedeemCodeFixtures.spend(of: 500, to: swept, leafIndex: 4)]
        )
        let codes = StoredValue([sender.id: RedeemCodeLedger(records: [Self.record(at: 1)], isDiscovered: true)])
        let balances = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        #expect(try await balances.outstandingCodes(of: sender.account, on: .devnet).isEmpty)
        #expect(await codes.value?[sender.id]?.records.isEmpty == true)
    }

    /// A code whose app quit before recording its funding is listed once the indexer reports its
    /// note, so the sender can still share or take it back; pending indices without notes leave only once their
    /// fundings can no longer land.
    @Test
    func `Pending codes with indexed notes are listed and expired ones leave`() async throws {
        let sender = try await Self.sender()
        let landed = try sender.keys.oneTimeAccount(at: 0)
        let responses = try RedeemCodeFixtures.responses(accounts: [
            landed.address: RedeemCodeFixtures.systemAccount(lamports: RedeemCodeFixtures.reserve),
        ], deposits: [try RedeemCodeFixtures.deposit(700, to: landed, leafIndex: 3)])
        let now = Date.now
        let codes = StoredValue([sender.id: RedeemCodeLedger(pending: [
            PendingRedeemCode(index: 0, created: now.addingTimeInterval(-7_200)),
            PendingRedeemCode(index: 1, created: now.addingTimeInterval(-7_200)),
            PendingRedeemCode(index: 2, created: now),
        ], isDiscovered: true)])
        let balances = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        let outstanding = try await balances.outstandingCodes(of: sender.account, on: .devnet)

        let record = RedeemCodeRecord(index: 0, amount: 700, reserve: RedeemCodeFixtures.reserve,
                                      created: now.addingTimeInterval(-7_200),
                                      fundingSignature: RedeemCodeFixtures.signature(ofDepositAt: 3))
        #expect(outstanding.map(\.record) == [record])
        #expect(await codes.value?[sender.id]?.records == [record])
        #expect(await codes.value?[sender.id]?.pending.map(\.index) == [2])
        #expect(await codes.value?[sender.id]?.nextIndex == 3)
    }

    /// Without a codes entry, listing scans the account's one-time accounts until a batch has none used, and keeps the
    /// codes whose notes are unspent, with their notes' amounts and their lamports as reserves.
    @Test
    func `Outstanding codes are found on chain without a codes entry`() async throws {
        let sender = try await Self.sender()
        let swept = try sender.keys.oneTimeAccount(at: 0)
        let held = try sender.keys.oneTimeAccount(at: 2)
        let responses = try RedeemCodeFixtures.responses(
            accounts: [held.address: RedeemCodeFixtures.systemAccount(lamports: 1_400_000)],
            deposits: [try RedeemCodeFixtures.deposit(500, to: swept, leafIndex: 3),
                       try RedeemCodeFixtures.deposit(700, to: held, leafIndex: 4)],
            spends: [try RedeemCodeFixtures.spend(of: 500, to: swept, leafIndex: 3)]
        )
        let codes = StoredValue<PrivateBalances.Codes>()
        let balances = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        let outstanding = try await balances.outstandingCodes(of: sender.account, on: .devnet)

        let record = try #require(outstanding.first?.record)
        #expect(outstanding.count == 1)
        #expect(record.index == 2)
        #expect(record.amount == 700)
        #expect(record.reserve == 1_400_000)
        #expect(record.fundingSignature == RedeemCodeFixtures.signature(ofDepositAt: 4))
        #expect(await codes.value?[sender.id]?.nextIndex == 3)
        #expect(await codes.value?[sender.id]?.isDiscovered == true)
    }

    /// A discovery reads batches of 500 tags, so it finds a code past a gap of more than 20
    /// unused indices that abandoned preparations left, and keeps it by its unspent note even when a lagging node
    /// reports no one-time account.
    @Test
    func `Discovery finds codes past a gap of unused indices`() async throws {
        let sender = try await Self.sender()
        let swept = try sender.keys.oneTimeAccount(at: 0)
        let held = try sender.keys.oneTimeAccount(at: 45)
        let responses = try RedeemCodeFixtures.responses(
            accounts: [:],
            deposits: [try RedeemCodeFixtures.deposit(500, to: swept, leafIndex: 3),
                       try RedeemCodeFixtures.deposit(700, to: held, leafIndex: 4)],
            spends: [try RedeemCodeFixtures.spend(of: 500, to: swept, leafIndex: 3)]
        )
        let codes = StoredValue<PrivateBalances.Codes>()
        let balances = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        let outstanding = try await balances.outstandingCodes(of: sender.account, on: .devnet)

        #expect(outstanding.map(\.record.index) == [45])
        #expect(outstanding.map(\.record.amount) == [700])
        #expect(await codes.value?[sender.id]?.nextIndex == 46)
        #expect(try await RedeemCodeFixtures.tagCounts(of: responses).prefix(2) == [500, 500])
    }

    /// An unreadable codes item is deleted once, and the account's codes are found on chain again.
    @Test
    func `An unreadable codes item is deleted and found again`() async throws {
        let sender = try await Self.sender()
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [])
        let codes = StoredValue<PrivateBalances.Codes>([sender.id: RedeemCodeLedger(isDiscovered: true)],
                                                       unreadable: true)
        let balances = try Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        #expect(try await balances.outstandingCodes(of: sender.account, on: .devnet).isEmpty)
        #expect(await codes.deletions == 1)
        #expect(await codes.value == [sender.id: RedeemCodeLedger(isDiscovered: true)])
    }

    /// Removing private balances deletes every account's codes with the keys and notes.
    @Test
    func `Removing private balances deletes the codes`() async throws {
        let sender = try await Self.sender()
        let codes = StoredValue([sender.id: RedeemCodeLedger(records: [Self.record(at: 0)], isDiscovered: true)])
        let balances = try Self.balances(RedeemCodeFixtures.responses(accounts: [:], deposits: []),
                                         keys: sender.storedKeys, notes: sender.notes, codes: codes)

        try await balances.removeAll()

        #expect(await codes.value == nil)
        #expect(await codes.deletions == 1)
    }

    /// Creates private balances around local responses and in-memory storage.
    /// - Parameters:
    ///   - responses: The local responses that every network's provider client sends requests to.
    ///   - keys: Each account's keys; empty storage by default.
    ///   - notes: Each account's notes; empty storage by default.
    ///   - codes: Each account's codes; empty storage by default.
    /// - Returns: Private balances whose requests never leave the process.
    /// - Throws: A validation error, which doesn't happen.
    private static func balances(_ responses: HTTPResponses, keys: StoredValue<PrivateBalances.Keys> = StoredValue(),
                                 notes: StoredValue<PrivateBalances.Notes> = StoredValue(),
                                 codes: StoredValue<PrivateBalances.Codes> = StoredValue()) throws -> PrivateBalances {
        PrivateBalances.inMemory(keys: keys, notes: notes, codes: codes, recovery: try PrivateBalanceFixtures.recoveryStore(),
                                 responses: responses)
    }

    /// Derives fixture account 0, registered with a notes entry, and a deposit of ``senderLamports`` to it.
    /// - Returns: The account, its keys, their storage, its notes, its notes entry, its deposit row, and its registry
    ///   record.
    /// - Throws: A derivation error.
    private static func sender() async throws -> (account: widgets.Account, keys: PrivateBalanceKeyRecord,
        storedKeys: StoredValue<PrivateBalances.Keys>, notes: StoredValue<PrivateBalances.Notes>, id: String,
        deposit: String, record: String) {
        let account = try await PrivateBalanceFixtures.account(index: 0)
        let keys = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try keys.shieldedAccount(for: account.address)
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        return (account, keys, StoredValue([account.address.value: keys]), StoredValue([id: NoteSyncState()]), id,
                try PrivateBalanceFixtures.deposit(senderLamports, to: shielded, leafIndex: 1),
                try PrivateBalanceFixtures.registryRecord(publishing: shielded))
    }

    /// Derives fixture account 1 with its keys, and a notes entry only when it's registered.
    /// - Parameter registered: Whether the account registered its keys.
    /// - Returns: The account, its shielded keys, their storage, its notes, its notes entry, and its registry record.
    /// - Throws: A derivation error.
    private static func recipient(registered: Bool) async throws -> (account: widgets.Account, shielded: ShieldedAccount,
        storedKeys: StoredValue<PrivateBalances.Keys>, notes: StoredValue<PrivateBalances.Notes>, id: String,
        record: String) {
        let account = try await PrivateBalanceFixtures.account(index: 1)
        let keys = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try keys.shieldedAccount(for: account.address)
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        return (account, shielded, StoredValue([account.address.value: keys]),
                StoredValue(registered ? [id: NoteSyncState()] : nil), id,
                try PrivateBalanceFixtures.registryRecord(publishing: shielded))
    }

    /// Creates the one-time account of a code that someone else created.
    /// - Returns: The one-time account of a fixed public secret.
    /// - Throws: A derivation error, which doesn't happen.
    private static func giftedAccount() throws -> OneTimeAccount {
        try OneTimeAccount(secret: SymmetricKey(data: Data(repeating: 9, count: 32)))
    }

    /// Creates a code's record.
    /// - Parameters:
    ///   - index: The code's index.
    ///   - amount: The code's amount.
    /// - Returns: The record.
    private static func record(at index: UInt32, amount: UInt64 = 1_000) -> RedeemCodeRecord {
        RedeemCodeRecord(index: index, amount: amount, reserve: RedeemCodeFixtures.reserve,
                         created: Date(timeIntervalSince1970: 0), fundingSignature: "funding")
    }

    /// Reads the index of a code's creation.
    /// - Parameter transaction: A prepared transaction.
    /// - Returns: The code's index, or `nil` for another transaction.
    private static func index(of transaction: PreparedPrivateTransaction) -> UInt32? {
        guard case .createCode(_, let index, _) = transaction.effect else { return nil }
        return index
    }

    /// Lists the RPC methods of the requests sent so far.
    /// - Parameter responses: The local responses that recorded the requests.
    /// - Returns: Each request's method, in arrival order.
    /// - Throws: A test prerequisite error for a request without a method.
    private static func methods(of responses: HTTPResponses) async throws -> [String] {
        try await responses.requests.map { try $0.rpcMethod }
    }
}
