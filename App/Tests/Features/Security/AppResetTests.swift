import Foundation
import Testing
import Transactions
@testable import Portfolio
@testable import RPC
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

    @Test(arguments: [.recovery, .privateBalances, .contacts, .appearance, .accounts] as [ResetStorage.Step])
    func `A failed step keeps the later steps, including the accounts, until a retry finishes the reset`(
        _ step: ResetStorage.Step
    ) async throws {
        let storage = ResetStorage(failingOnce: step)
        let reset = AppReset(storage: storage)
        let order = ResetStorage.Step.allCases

        await #expect(throws: CocoaError.self) { try await reset.reset() }
        #expect(await storage.deletions == Array(order.prefix { $0 != step }))

        try await reset.reset()
        #expect(await Array(storage.deletions.suffix(order.count)) == order)
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
        let responses = HTTPResponses(["getMultipleAccounts": [AccountReplies.accounts([nil])]],
                                      gate: gate, heldMethod: "getMultipleAccounts")
        let rpcStore = RPCStore.inMemory()
        let service = Portfolio(rpc: responses.rpcProvider(network: .devnet, rpcStore: rpcStore),
                                store: FileSnapshotStore(directory: storage.directory),
                                tokenLists: FileTokenListStore(directory: storage.directory.appending(path: "TokenLists")))
        let portfolios = PortfolioStore(prices: JupiterPriceProvider(transport: responses), currency: .inMemory(),
                                        rpcStore: rpcStore, priceStore: .inMemory()) { _, _ in service }
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
