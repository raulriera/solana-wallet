import Foundation
@testable import Portfolio
@testable import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppResetTests {
    @Test
    func `Reset deletes the secrets, each shared store, the directories, appearance, then the accounts`() async throws {
        let storage = ResetStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        try createFile(in: storage.directory)

        try await AppReset(storage: storage).reset()

        #expect(await storage.deletions == ResetStorage.Step.allCases)
        let existed = Array(repeating: true, count: ResetStorage.Step.allCases.count - 2) + [false, false]
        #expect(await storage.directoryExisted == existed)
    }

    @Test(arguments: ResetStorage.Step.allCases)
    func `Retrying after a failed step finishes the reset`(_ step: ResetStorage.Step) async throws {
        let storage = ResetStorage(failingOnce: step)
        let reset = AppReset(storage: storage)
        let order = ResetStorage.Step.allCases

        await #expect(throws: CocoaError.self) { try await reset.reset() }
        #expect(await storage.deletions == Array(order.prefix { $0 != step }))

        try await reset.reset()
        #expect(await Array(storage.deletions.suffix(order.count)) == order)
    }

    @Test(arguments: ResetStorage.Step.allCases.filter { $0 != .accounts })
    func `A failed earlier step keeps the accounts`(_ step: ResetStorage.Step) async throws {
        let storage = ResetStorage(failingOnce: step)
        let account = try Account.fixture(index: 0)
        let accounts = AccountStore.inMemory(StoredValue([account]))
        await accounts.load()
        let reset = AppReset(recovery: storage, privateBalances: storage.privateBalances,
                             directories: [storage.directory], appearance: storage.appearance, stores: storage.stores,
                             accounts: accounts)

        await #expect(throws: CocoaError.self) { try await reset.reset() }

        #expect(accounts.accounts == [account])
    }

    @Test
    func `Retrying after a directory can't be deleted finishes the reset`() async throws {
        let storage = ResetStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        try createFile(in: storage.directory)
        let reset = AppReset(storage: storage)
        try setPermissions(0o555, of: storage.directory)

        await #expect(throws: CocoaError.self) { try await reset.reset() }
        #expect(await storage.deletions == Array(ResetStorage.Step.allCases.prefix { $0 != .appearance }))

        try setPermissions(0o755, of: storage.directory)
        try await reset.reset()
        #expect(!FileManager.default.fileExists(atPath: storage.directory.path))
    }

    @Test
    func `A balance read that runs during a reset saves nothing afterward`() async throws {
        let storage = ResetStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        let gate = Suspension()
        let responses = HTTPResponses(["getMultipleAccounts": [#"{"context":{"slot":1},"value":[null]}"#]],
                                      gate: gate, heldMethod: "getMultipleAccounts")
        let providers = ProviderStore.inMemory()
        let service = Portfolio(rpc: responses.providerClient(network: .devnet, providers: providers),
                                store: FileSnapshotStore(directory: storage.directory),
                                tokenLists: FileTokenListStore(directory: storage.directory.appending(path: "TokenLists")))
        let portfolios = PortfolioStore(prices: Jupiter(transport: responses), currency: .inMemory(),
                                        providers: providers) { _, _ in service }
        let account = try Account.publicWallet()
        let viewing = Task { await portfolios.observe(account, on: .devnet) }
        defer { viewing.cancel() }
        await gate.waitUntilStarted()

        try await AppReset(recovery: storage, privateBalances: storage.privateBalances, directories: [storage.directory],
                           appearance: storage.appearance, stores: [portfolios], accounts: storage.accounts).reset()
        gate.resume()
        await service.reload(for: account.address.value)

        #expect(!FileManager.default.fileExists(atPath: storage.directory.path))
        viewing.cancel()
        await viewing.value
    }

    private func createFile(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("saved".utf8).write(to: directory.appending(path: "file.json"))
    }

    private func setPermissions(_ permissions: Int, of directory: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: directory.path)
    }
}
