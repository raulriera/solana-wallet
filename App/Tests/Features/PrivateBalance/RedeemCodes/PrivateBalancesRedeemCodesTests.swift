import CryptoKit
import Foundation
import Testing
import Transactions
import Wallet
@testable import Privacy
@testable import RPC
@testable import widgets

@Suite(.timeLimit(.minutes(1)))
struct PrivateBalancesRedeemCodesTests {
    private static let senderLamports: UInt64 = 5_000_000

    @Test
    func `Creating a code funds the next unused one-time account`() async throws {
        let sender = try await Self.sender()
        let used = try sender.keys.oneTimeAccount(at: 0)
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [
            sender.deposit, try RedeemCodeFixtures.deposit(1, to: used, leafIndex: 9),
        ])
        let codes = StoredValue<PrivateBalances.Codes>()
        let balances = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        let prepared = try await balances.prepare(.createCode(1_000_000), from: sender.account, on: .devnet)

        let (spend, index, reserve) = try #require(prepared.effect.codeCreation)
        #expect(index == 1)
        #expect(reserve == RedeemCodeFixtures.reserve)
        #expect(spend.amount == 1_000_000)
        #expect(spend.receivedAmount == Self.senderLamports - 1_000_000 - reserve)
        let transact = try #require(spend.instructions.last)
        #expect(spend.instructions.count == 1)
        #expect(transact.accounts.last?.address.value == (try sender.keys.oneTimeAccount(at: 1)).address)
        #expect(try prepared.authorities.map { try $0.address } == [sender.account.address])
        #expect(prepared.instructions == spend.instructions)
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

    @Test
    func `Concurrent codes take different indices and a dropped code's index isn't reused`() async throws {
        let sender = try await Self.sender()
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [sender.deposit])
        let codes = StoredValue<PrivateBalances.Codes>()
        let balances = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

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

    @Test
    func `A failed record save keeps the code's index pending`() async throws {
        let sender = try await Self.sender()
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [sender.deposit])
        let codes = StoredValue<PrivateBalances.Codes>()
        let balances = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)
        let prepared = try await balances.prepare(.createCode(1_000), from: sender.account, on: .devnet)
        await codes.failSaving()

        await #expect(throws: CocoaError.self) {
            try await balances.complete(prepared, with: PrivateBalanceFixtures.confirmation(.succeeded, signature: "funding"))
        }
        #expect(await codes.value?[sender.id]?.pending.map(\.index) == [0])
    }

    @Test
    func `Creating a code from too many notes fails without a proof`() async throws {
        let sender = try await Self.sender()
        let shielded = try sender.keys.shieldedAccount(for: sender.account.address)
        let deposits = try (1...50).map {
            try PrivateBalanceFixtures.deposit(1_000_000, to: shielded, leafIndex: UInt64($0), of: .nativeSOL)
        }
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: deposits)
        let balances = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes)

        await #expect(throws: PrivateBalanceError.tooManyNotes) {
            try await balances.prepare(.createCode(41_000_000), from: sender.account, on: .devnet)
        }
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 0)
    }

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

    @Test
    func `Redeeming into a registered account sweeps the code`() async throws {
        let recipient = try await Self.recipient(registered: true)
        let oneTime = try Self.giftedAccount()
        let responses = try RedeemCodeFixtures.responses(accounts: [
            oneTime.address: RedeemCodeFixtures.systemAccount(lamports: RedeemCodeFixtures.reserve),
            try RedeemCodeFixtures.recordAddress(of: recipient.account): recipient.record,
        ], deposits: [try RedeemCodeFixtures.deposit(1_000_000, to: oneTime, leafIndex: 3)])
        let balances = try await Self.balances(responses, keys: recipient.storedKeys, notes: recipient.notes)
        let code = try RedeemCode(secret: oneTime.secret, network: .devnet)

        let prepared = try await balances.prepare(.redeem(code), from: recipient.account, on: .devnet)

        guard case .redeem(let redemption) = prepared.effect else {
            Issue.record("Expected a redemption.")
            return
        }
        #expect(redemption.availableLamports == RedeemCodeFixtures.reserve - RedeemCodeFixtures.treeFee)
        #expect(redemption.noteLamports == 1_000_000)
        #expect(redemption.takenBackIndex == nil)
        #expect(!prepared.registers)
        #expect(try prepared.authorities.map { try $0.address } == [Address(oneTime.address)])
        #expect(prepared.instructions.count == 2)
        #expect(prepared.instructions.last == (try ShieldedPool.deposit(
            redemption.availableLamports, of: .nativeSOL, from: Address(oneTime.address),
            to: recipient.shielded.recipient, treeID: 1
        )))

        let charged = try prepared.withNetworkFee(5_000)
        let status = try await balances.complete(charged, with: PrivateBalanceFixtures.confirmation(.succeeded))

        let deposited = 1_000_000 + RedeemCodeFixtures.reserve - RedeemCodeFixtures.treeFee - 5_000
        #expect(status == .balance(available: 0, pending: deposited, of: .nativeSOL))
        #expect(await recipient.notes.value?[recipient.id]?.pendingAmount(of: .nativeSOL) == deposited)
    }

    @Test
    func `Redeeming into an unregistered account registers it`() async throws {
        let recipient = try await Self.recipient(registered: false)
        let oneTime = try Self.giftedAccount()
        let responses = try RedeemCodeFixtures.responses(accounts: [
            oneTime.address: RedeemCodeFixtures.systemAccount(lamports: RedeemCodeFixtures.reserve),
        ], deposits: [try RedeemCodeFixtures.deposit(1_000_000, to: oneTime, leafIndex: 3)])
        let balances = try await Self.balances(responses, keys: recipient.storedKeys, notes: recipient.notes)

        let prepared = try await balances.prepare(.redeem(RedeemCode(secret: oneTime.secret, network: .devnet)),
                                                  from: recipient.account, on: .devnet)
        let charged = try prepared.withNetworkFee(2 * Redemption.signatureFee)

        let deposited = 1_000_000 + RedeemCodeFixtures.treeFee
        #expect(prepared.registers)
        #expect(try prepared.authorities.map { try $0.address } == [Address(oneTime.address), recipient.account.address])
        #expect(prepared.instructions.first == (try recipient.shielded.register(paidBy: Address(oneTime.address))))
        #expect(prepared.instructions.count == 3)
        #expect(try await balances.complete(charged, with: PrivateBalanceFixtures.confirmation(.succeeded)) == .balance(available: 0, pending: deposited, of: .nativeSOL))
        #expect(await recipient.notes.value?[recipient.id]?.pendingAmount(of: .nativeSOL) == deposited)
    }

    @Test
    func `Redeeming into another output tree pays both trees' fees from the reserve`() async throws {
        let recipient = try await Self.recipient(registered: false)
        let oneTime = try Self.giftedAccount()
        let responses = try RedeemCodeFixtures.responses(accounts: [
            oneTime.address: RedeemCodeFixtures.systemAccount(lamports: RedeemCodeFixtures.reserve),
            try ShieldedPool.tree(id: 0).value: UTXOTrees.emptyTree(feePerTree: 100),
            try ShieldedPool.tree(id: 1).value: UTXOTrees.emptyTree(feePerTree: RedeemCodeFixtures.treeFee),
        ], deposits: [try RedeemCodeFixtures.deposit(1_000_000, to: oneTime, leafIndex: 3)], outputTreeID: 0)
        let balances = try await Self.balances(responses, keys: recipient.storedKeys, notes: recipient.notes)

        let prepared = try await balances.prepare(.redeem(RedeemCode(secret: oneTime.secret, network: .devnet)),
                                                  from: recipient.account, on: .devnet)

        guard case .redeem(let redemption) = prepared.effect else {
            Issue.record("Expected a redemption.")
            return
        }
        #expect(redemption.availableLamports == 2 * Redemption.signatureFee + RedeemCodeFixtures.treeFee - 100)
    }

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
        let balances = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        let prepared = try await balances.prepare(.takeBack(index: 1), from: sender.account, on: .devnet)
        guard case .redeem(let redemption) = prepared.effect else {
            Issue.record("Expected a redemption.")
            return
        }
        let charged = try prepared.withNetworkFee(5_000)
        _ = try await balances.complete(charged, with: PrivateBalanceFixtures.confirmation(.succeeded))

        #expect(redemption.takenBackIndex == 1)
        #expect(await sender.storedKeys.loads == 2)
        #expect(try prepared.authorities.map { try $0.address } == [Address(oneTime.address)])
        #expect(await codes.value?[sender.id]?.records.map(\.index) == [0])
        #expect(await codes.value?[sender.id]?.nextIndex == 2)
        #expect(await sender.notes.value?[sender.id]?.pendingAmount(of: .nativeSOL) == 1_000 + RedeemCodeFixtures.reserve
            - RedeemCodeFixtures.treeFee - 5_000)
    }

    @Test
    func `Outstanding codes follow the indexer once their reserves are swept`() async throws {
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
        let balances = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        let outstanding = try await balances.outstandingCodes(of: sender.account, on: .devnet)

        let expected = [Self.record(at: 0, amount: 700), Self.record(at: 1)]
        #expect(outstanding.map(\.record) == expected)
        #expect(outstanding.map(\.code) == [try RedeemCode(secret: held.secret, network: .devnet),
                                            try RedeemCode(secret: sender.keys.oneTimeAccount(at: 1).secret,
                                                           network: .devnet)])
        #expect(await codes.value?[sender.id]?.records == expected)
        #expect(await PrivateBalanceFixtures.nonTreeAccountReads(of: responses) == 1)
    }

    @Test
    func `Codes whose notes aren't confirmed aren't ready to redeem`() async throws {
        let sender = try await Self.sender()
        let oneTime = try sender.keys.oneTimeAccount(at: 1)
        let accounts = [
            try RedeemCodeFixtures.recordAddress(of: sender.account): sender.record,
            oneTime.address: RedeemCodeFixtures.systemAccount(lamports: RedeemCodeFixtures.reserve),
        ]
        let deposits = [sender.deposit, try RedeemCodeFixtures.deposit(1_000, to: oneTime, leafIndex: 3)]
        let responses = try RedeemCodeFixtures.responses(accounts: accounts, deposits: deposits, isFinalized: false)
        let code = try RedeemCode(secret: oneTime.secret, network: .devnet)

        await #expect(throws: PrivateBalanceError.codeNotReady) {
            try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes)
                .prepare(.redeem(code), from: sender.account, on: .devnet)
        }
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 0)
    }

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
        let balances = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

        let outstanding = try await balances.outstandingCodes(of: sender.account, on: .devnet)

        let record = RedeemCodeRecord(index: 0, amount: 700, reserve: RedeemCodeFixtures.reserve,
                                      created: now.addingTimeInterval(-7_200),
                                      fundingSignature: RedeemCodeFixtures.signature(ofDepositAt: 3))
        #expect(outstanding.map(\.record) == [record])
        #expect(await codes.value?[sender.id]?.records == [record])
        #expect(await codes.value?[sender.id]?.pending.map(\.index) == [2])
        #expect(await codes.value?[sender.id]?.nextIndex == 3)
    }

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
        let balances = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes, codes: codes)

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

    @Test
    func `A first discovery reads each code's fundings, notes, and lamports once`() async throws {
        let sender = try await Self.sender()
        let held = try sender.keys.oneTimeAccount(at: 0)
        let responses = try RedeemCodeFixtures.responses(
            accounts: [held.address: RedeemCodeFixtures.systemAccount(lamports: 1_400_000)],
            deposits: [try RedeemCodeFixtures.deposit(700, to: held, leafIndex: 3)]
        )
        let balances = try await Self.balances(responses, keys: sender.storedKeys, notes: sender.notes)

        let outstanding = try await balances.outstandingCodes(of: sender.account, on: .devnet)

        #expect(outstanding.map(\.record.index) == [0])
        #expect(try await RedeemCodeFixtures.tagCounts(of: responses) == [500, 500, 2])
        #expect(await PrivateBalanceFixtures.nonTreeAccountReads(of: responses) == 1)
    }

    @Test
    func `Discovery runs again while a found code's notes aren't confirmed`() async throws {
        let sender = try await Self.sender()
        let held = try sender.keys.oneTimeAccount(at: 0)
        let deposits = [try RedeemCodeFixtures.deposit(700, to: held, leafIndex: 3)]
        let accounts = [held.address: RedeemCodeFixtures.systemAccount(lamports: 1_400_000)]
        let lagging = try RedeemCodeFixtures.responses(accounts: accounts, deposits: deposits, isFinalized: false)
        let finalized = try RedeemCodeFixtures.responses(accounts: accounts, deposits: deposits)
        let codes = StoredValue<PrivateBalances.Codes>()

        let unconfirmed = try await Self.balances(lagging, keys: sender.storedKeys, notes: sender.notes, codes: codes)
            .outstandingCodes(of: sender.account, on: .devnet)
        let undiscovered = await codes.value?[sender.id]
        let confirmed = try await Self.balances(finalized, keys: sender.storedKeys, notes: sender.notes, codes: codes)
            .outstandingCodes(of: sender.account, on: .devnet)

        #expect(unconfirmed.isEmpty)
        #expect(undiscovered?.records.isEmpty == true)
        #expect(undiscovered?.isDiscovered == false)
        #expect(undiscovered?.nextIndex == 1)
        #expect(confirmed.map(\.record.index) == [0])
        #expect(confirmed.map(\.record.amount) == [700])
        #expect(confirmed.map(\.record.reserve) == [1_400_000])
        #expect(confirmed.map(\.record.fundingSignature) == [RedeemCodeFixtures.signature(ofDepositAt: 3)])
        #expect(await codes.value?[sender.id]?.isDiscovered == true)
    }

    @Test
    func `Removing private balances deletes the codes`() async throws {
        let sender = try await Self.sender()
        let codes = StoredValue([sender.id: RedeemCodeLedger(records: [Self.record(at: 0)], isDiscovered: true)])
        let balances = try await Self.balances(RedeemCodeFixtures.responses(accounts: [:], deposits: []),
                                               keys: sender.storedKeys, notes: sender.notes, codes: codes)

        try await balances.removeAll()

        #expect(await codes.value == nil)
        #expect(await codes.deletions == 1)
    }

    @Test
    func `Outstanding codes with a provider that doesn't serve private balances are unavailable`() async throws {
        let sender = try await Self.sender()
        let responses = try RedeemCodeFixtures.responses(accounts: [:], deposits: [])
        let balances = await PrivateBalances.inMemory(keys: sender.storedKeys, notes: sender.notes,
                                                      recovery: try PrivateBalanceFixtures.recoveryStore(),
                                                      responses: responses, provider: .solana)

        await #expect(throws: PrivateBalanceError.unavailable) {
            _ = try await balances.outstandingCodes(of: sender.account, on: .devnet)
        }
        #expect(await responses.requests.isEmpty)
    }

    @MainActor
    private static func balances(_ responses: HTTPResponses, keys: StoredValue<PrivateBalances.Keys> = StoredValue(),
                                 notes: StoredValue<PrivateBalances.Notes> = StoredValue(),
                                 codes: StoredValue<PrivateBalances.Codes> = StoredValue()) throws -> PrivateBalances {
        PrivateBalances.inMemory(keys: keys, notes: notes, codes: codes, recovery: try PrivateBalanceFixtures.recoveryStore(),
                                 responses: responses)
    }

    private static func sender() async throws -> (account: widgets.Account, keys: PrivateBalanceKeyRecord,
        storedKeys: StoredValue<PrivateBalances.Keys>, notes: StoredValue<PrivateBalances.Notes>, id: String,
        deposit: String, record: String) {
        let account = try await PrivateBalanceFixtures.account(index: 0)
        let keys = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try keys.shieldedAccount(for: account.address)
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        return (account, keys, StoredValue([account.address.value: keys]), StoredValue([id: NoteSyncState()]), id,
                try PrivateBalanceFixtures.deposit(senderLamports, to: shielded, leafIndex: 1, of: .nativeSOL),
                try PrivateBalanceFixtures.registryRecord(publishing: shielded))
    }

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

    private static func giftedAccount() throws -> OneTimeAccount {
        try OneTimeAccount(secret: SymmetricKey(data: Data(repeating: 9, count: 32)))
    }

    private static func record(at index: UInt32, amount: UInt64 = 1_000) -> RedeemCodeRecord {
        RedeemCodeRecord(index: index, amount: amount, reserve: RedeemCodeFixtures.reserve,
                         created: Date(timeIntervalSince1970: 0), fundingSignature: "funding")
    }

    private static func index(of transaction: PreparedPrivateTransaction) -> UInt32? {
        guard case .createCode(_, let index, _) = transaction.effect else { return nil }
        return index
    }
}
