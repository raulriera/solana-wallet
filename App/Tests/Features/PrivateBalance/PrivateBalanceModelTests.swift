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
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes())
        #expect(model.status == nil)

        await model.refresh(for: account)

        #expect(model.status == .off)
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

        #expect(model.status == .off)
    }

    /// Another account starts over: its status replaces the last account's, so nothing shows for an account without
    /// private-balance keys.
    @Test
    func `Another account starts over`() async throws {
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes())
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
        #expect(model.status == .off)
        #expect(!model.isTurnedOn)
        #expect(!model.isTurningOn)
    }

    /// Dismissing authentication turns nothing on and shows no error.
    @Test
    func `Cancelled authentication shows no error`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(),
                                   recovery: SecurityRecoveryStore(readError: CancellationError()))
        await model.refresh(for: account)

        model.turnOn()
        await model.run(model.attempt)

        #expect(model.error == nil)
        #expect(model.status == .off)
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

    /// The fixture account's address at a path without private-balance keys.
    /// - Returns: The account.
    /// - Throws: A derivation or test prerequisite error.
    private static func otherPathAccount() async throws -> widgets.Account {
        let fixture = try await PrivateBalanceFixtures.account()
        return widgets.Account(id: UUID(), recoveryID: PrivateBalanceFixtures.recoveryID, address: fixture.address,
                               path: try DerivationPath("m/44'/501'/0'"))
    }
}
