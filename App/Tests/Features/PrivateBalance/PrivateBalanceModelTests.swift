import Foundation
import Privacy
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Checks a window's private balance and turning it on through real private balances and local indexer fixtures.
@MainActor
struct PrivateBalanceModelTests {
    /// Nothing shows before the first refresh; a refresh shows why the account has no balance yet.
    @Test
    func `A refresh shows the account's status`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        #expect(model.status == nil)

        await model.refresh(for: account)

        #expect(model.status == .off(isRegistered: false))
    }

    /// An account at a path without private-balance keys shows nothing and reads nothing.
    @Test
    func `An account at another path shows nothing`() async throws {
        let responses = HTTPResponses.privateNotes()
        let model = try PrivateBalanceModel.fixture(responses)

        await model.refresh(for: try await Self.otherPathAccount())

        #expect(model.status == nil)
        #expect(await responses.requests.isEmpty)
    }

    /// A refresh that fails keeps the status that the last refresh read.
    @Test
    func `A failed refresh keeps the last status`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue<PrivateBalances.Keys>()
        let responses = HTTPResponses.privateNotes(error: .http(statusCode: 429, retryAfter: nil))
        let model = try PrivateBalanceModel.fixture(responses, keys: keys)
        await model.refresh(for: account)
        try await keys.save([account.address.value: PrivateBalanceFixtures.keys(for: account)])

        await model.refresh()

        #expect(model.status == .off(isRegistered: false))
    }

    /// Another account starts over: its status replaces the last account's, so nothing shows for an account without
    /// private-balance keys.
    @Test
    func `Another account starts over`() async throws {
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        await model.refresh(for: try await PrivateBalanceFixtures.account())

        await model.refresh(for: try await Self.otherPathAccount())

        #expect(model.status == nil)
    }

    /// A registered account with SOL in its private balance has a balance; one without SOL doesn't.
    @Test
    func `Only private SOL counts as a balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try record.shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(
            registry: [try PrivateBalanceFixtures.registry(publishing: shielded)],
            deposits: [try PrivateBalanceFixtures.deposit(1_000_000, to: shielded, leafIndex: 4)]
        )
        let funded = try PrivateBalanceModel.fixture(responses, keys: StoredValue([account.address.value: record]))
        let unfunded = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
                                      keys: StoredValue([account.address.value: record]))

        await funded.refresh(for: account)
        await unfunded.refresh(for: account)

        #expect(funded.status == .balance(available: 1_000_000, pending: 0))
        #expect(funded.hasBalance)
        #expect(unfunded.status == .unregistered)
        #expect(!unfunded.hasBalance)
    }

    /// While private balances are on, adding opens a move of the account's public SOL into its private balance; while
    /// they're off, nothing opens.
    /// - Parameter isOn: Whether the account turned private balances on.
    @Test(arguments: [true, false])
    func `Adding opens a deposit only while private balances are on`(isOn: Bool) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys: PrivateBalances.Keys = isOn ? [account.address.value: try await PrivateBalanceFixtures.keys(for: account)] : [:]
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
                                                    keys: StoredValue(keys))
        await model.refresh(for: account)

        model.addToPrivateBalance(publicLamports: 2_000_000_000)

        #expect((model.move != nil) == isOn)
        #expect(model.move?.direction == (isOn ? .toPrivate : nil))
        #expect(model.move?.payment.source == (isOn ? .publicBalance : nil))
        #expect(model.move?.payment.token.balance == (isOn ? 2 : nil))
        #expect(model.error == nil)
    }

    /// Moving to the public balance opens a withdrawal of the available private SOL only while there's some; pending
    /// SOL alone, or an unregistered account, opens nothing.
    /// - Parameter status: The account's private balance.
    @Test(arguments: [PrivateBalanceStatus.balance(available: 1_000_000, pending: 0),
                      .balance(available: 0, pending: 1_000_000), .unregistered])
    func `Moving to the public balance opens a withdrawal only with available SOL`(status: PrivateBalanceStatus) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(
            HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
            keys: StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        )
        await model.refresh(for: account)
        model.show(status)

        model.moveToPublicBalance()

        let opens = status == .balance(available: 1_000_000, pending: 0)
        #expect(model.availableLamports == (opens ? 1_000_000 : nil))
        #expect(model.move?.direction == (opens ? .toPublic : nil))
        #expect(model.move?.payment.source == (opens ? .privateBalance : nil))
        #expect(model.move?.payment.token.balance == (opens ? Decimal(string: "0.001") : nil))
        #expect(model.error == nil)
    }

    /// A network without a transaction coordinator opens no deposit and explains that the transaction can't be
    /// prepared.
    @Test
    func `Adding without a transaction coordinator fails`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(
            HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
            keys: StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)]),
            transactions: NetworkTransactions { _ in throw SubmitterError.noProviders }
        )
        await model.refresh(for: account)

        model.addToPrivateBalance(publicLamports: 2_000_000_000)

        #expect(model.move == nil)
        #expect(model.error == .preparationFailed)
    }

    /// A settled transaction's balance shows at once; pending SOL starts a follow-up of at most ten quick reads, and
    /// nothing pending starts none.
    /// - Parameters:
    ///   - pending: The settled balance's pending lamports.
    ///   - followsUp: Whether the model follows up.
    @Test(arguments: [(UInt64(1_000_000), true), (0, false)])
    func `A settled balance with pending SOL starts a follow-up`(pending: UInt64, followsUp: Bool) async throws {
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        await model.refresh(for: try await PrivateBalanceFixtures.account())

        model.show(.balance(available: 0, pending: pending))

        #expect(model.status == .balance(available: 0, pending: pending))
        #expect(model.isFollowingUp == followsUp)
        #expect(model.followUpReadsLeft == (followsUp ? PrivateBalanceModel.followUpReads : 0))
        #expect(model.followUp == (followsUp ? 1 : 0))
    }

    /// Each follow-up poll uses one quick read, and a read that finds nothing pending ends the follow-up.
    @Test
    func `A follow-up ends once nothing is pending`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [registry]),
                                                    keys: StoredValue([account.address.value: record]))
        await model.refresh(for: account)
        model.show(.balance(available: 0, pending: 1_000_000))

        await model.poll()

        #expect(model.status == .balance(available: 0, pending: 0))
        #expect(!model.isFollowingUp)
    }

    /// Without an account, a settled balance has nothing to show.
    @Test
    func `A settled balance without an account shows nothing`() throws {
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes())

        model.show(.balance(available: 0, pending: 1_000_000))

        #expect(model.status == nil)
        #expect(!model.isFollowingUp)
    }

    /// Turning on keeps the account's keys, then shows its balance and reports that it's on.
    @Test
    func `Turning on keeps the keys and shows the balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue<PrivateBalances.Keys>()
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]), keys: keys)
        await model.refresh(for: account)

        model.turnOn()
        #expect(model.isTurningOn)
        await model.run(model.attempt)

        #expect(model.status == .unregistered)
        #expect(model.isTurnedOn)
        #expect(!model.isTurningOn)
        #expect(model.error == nil)
        #expect(await keys.value == [account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
    }

    /// Keys that another app registered for the account fail turning on with that error, and private balances stay
    /// off.
    @Test
    func `Turning on an account registered with other keys fails`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let other = try PrivateBalanceFixtures.otherKeys(for: account.address)
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [try PrivateBalanceFixtures.registry(publishing: other)]))
        await model.refresh(for: account)

        model.turnOn()
        await model.run(model.attempt)

        #expect(model.error == .registeredWithOtherKeys)
        #expect(model.status == .off(isRegistered: true))
        #expect(!model.isTurnedOn)
        #expect(!model.isTurningOn)
    }

    /// Dismissing authentication turns nothing on and shows no error.
    @Test
    func `Cancelled authentication shows no error`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
                                   recovery: SecurityRecoveryStore(readError: CancellationError()))
        await model.refresh(for: account)

        model.turnOn()
        await model.run(model.attempt)

        #expect(model.error == nil)
        #expect(model.status == .off(isRegistered: false))
        #expect(!model.isTurnedOn)
        #expect(!model.isTurningOn)
    }

    /// Another failure, such as a rate-limited registration check, fails turning on with a typed error.
    @Test
    func `Other failures fail turning on`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered],
                                                   error: .http(statusCode: 429, retryAfter: nil))
        let model = try PrivateBalanceModel.fixture(responses)
        await model.refresh(for: account)

        model.turnOn()
        await model.run(model.attempt)

        #expect(model.error == .turnOnFailed)
        #expect(!model.isTurnedOn)
    }

    /// A second request while one waits keeps the first attempt, and a stale attempt runs nothing.
    @Test
    func `One attempt runs at a time`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let recovery = try PrivateBalanceFixtures.recoveryStore()
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
                                   recovery: recovery)
        await model.refresh(for: account)

        model.turnOn()
        let first = model.attempt
        model.turnOn()
        await model.run(UUID())

        #expect(model.attempt == first)
        #expect(await recovery.reads.isEmpty)
    }

    /// A poll reads the balance again only while private balances are on; off, it reads nothing.
    /// - Parameter isOn: Whether the account has private-balance keys.
    @Test(arguments: [true, false])
    func `Polls read only while private balances are on`(isOn: Bool) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys: PrivateBalances.Keys? = isOn ? [account.address.value: try await PrivateBalanceFixtures.keys(for: account)] : nil
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let model = try PrivateBalanceModel.fixture(responses, keys: StoredValue(keys))
        await model.refresh(for: account)
        let refreshRequests = await responses.requests.count

        await model.poll()

        let polled = await responses.requests.count > refreshRequests
        #expect(polled == isOn)
    }

    /// A missing key pauses polling, so polls send nothing even once the key is back, until a refresh succeeds.
    @Test
    func `Paused polling waits for a refresh that succeeds`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let providerKey = StoredValue("fixture-key")
        let balances = PrivateBalances(recovery: try PrivateBalanceFixtures.recoveryStore(), wallet: Wallet(),
                                       keys: StoredValue([account.address.value: record]), notes: StoredValue(),
                                       codes: StoredValue()) { network in
            responses.providerClient(network: network, settings: StoredValue(ProviderSettings(selection: .helius)),
                                     providerKey: providerKey)
        }
        let model = PrivateBalanceModel(balances: balances, transactions: .unused, network: .devnet)
        await model.refresh(for: account)

        try await providerKey.delete()
        await model.poll()
        let isPaused = model.isPollingPaused
        try await providerKey.save("fixture-key")
        let pausedRequests = await responses.requests.count
        await model.poll()
        let pausedPollRequests = await responses.requests.count - pausedRequests
        await model.refresh()

        #expect(isPaused)
        #expect(pausedPollRequests == 0)
        #expect(!model.isPollingPaused)
        #expect(model.status == .unregistered)
    }

    /// A failure that can clear by itself, such as a server error, keeps polling.
    @Test
    func `A failure that can clear by itself keeps polling`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(error: .http(statusCode: 503, retryAfter: nil)),
                                                    keys: keys)

        await model.refresh(for: account)

        #expect(!model.isPollingPaused)
    }

    /// A rate limit pauses polling.
    @Test
    func `A rate limit pauses polling`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(error: .http(statusCode: 429, retryAfter: nil)),
                                                    keys: keys)

        await model.refresh(for: account)

        #expect(model.isPollingPaused)
    }

    /// The fixture account's address at a path without private-balance keys.
    /// - Returns: The account.
    /// - Throws: A derivation or test prerequisite error.
    private static func otherPathAccount() async throws -> widgets.Account {
        let fixture = try await PrivateBalanceFixtures.account()
        return widgets.Account(id: UUID(), recoveryID: PrivateBalanceFixtures.recoveryID, address: fixture.address,
                               path: try DerivationPath("m/44'/501'/0'"))
    }
}
