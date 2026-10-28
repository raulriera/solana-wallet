import Foundation
@testable import Portfolio
@testable import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies the reset's deletion order, its window signal, and retries, without touching real storage.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppResetTests {
    /// Secrets go first, the shared stores end their work before the directories are deleted, appearance forgets them
    /// after, and every window hears about the reset only once everything is deleted.
    @Test
    func `Reset deletes the secrets, each shared store, the directories, then appearance`() async throws {
        let storage = ResetStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        try createFile(in: storage.directory)
        let revision = Revision()

        try await AppReset(storage: storage, revision: revision).reset()

        #expect(await storage.deletions == ResetStorage.Step.allCases)
        // Only appearance restarts after the directories are deleted.
        let existed = Array(repeating: true, count: ResetStorage.Step.allCases.count - 1) + [false]
        #expect(await storage.directoryExisted == existed)
        #expect(revision.value == 1)
    }

    /// A failed step stops the reset and keeps windows where they are; trying again finishes it.
    /// - Parameter step: The store whose first deletion fails.
    @Test(arguments: ResetStorage.Step.allCases)
    func `Retrying after a failed step finishes the reset`(_ step: ResetStorage.Step) async throws {
        let storage = ResetStorage(failingOnce: step)
        let revision = Revision()
        let reset = AppReset(storage: storage, revision: revision)
        let order = ResetStorage.Step.allCases

        await #expect(throws: CocoaError.self) { try await reset.reset() }
        #expect(await storage.deletions == Array(order.prefix { $0 != step }))
        #expect(revision.value == 0)

        try await reset.reset()
        #expect(await Array(storage.deletions.suffix(order.count)) == order)
        #expect(revision.value == 1)
    }

    /// A directory that can't be deleted stops the reset before appearance; trying again finishes it.
    @Test
    func `Retrying after a directory can't be deleted finishes the reset`() async throws {
        let storage = ResetStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        try createFile(in: storage.directory)
        let revision = Revision()
        let reset = AppReset(storage: storage, revision: revision)
        // A read-only directory keeps the file inside it.
        try setPermissions(0o555, of: storage.directory)

        await #expect(throws: CocoaError.self) { try await reset.reset() }
        #expect(await storage.deletions == ResetStorage.Step.allCases.filter { $0 != .appearance })
        #expect(revision.value == 0)

        try setPermissions(0o755, of: storage.directory)
        try await reset.reset()
        #expect(!FileManager.default.fileExists(atPath: storage.directory.path))
        #expect(revision.value == 1)
    }

    /// A balance read that runs during a reset ends with it, so it can't save the deleted wallet's holdings into the
    /// deleted directory afterward.
    /// - Throws: A test prerequisite error.
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
                           appearance: storage.appearance, stores: [portfolios], revision: Revision()).reset()
        gate.resume()
        // A reload returns once a read ends, so a read that the reset left running has saved by then.
        await service.reload(for: account.address.value)

        #expect(!FileManager.default.fileExists(atPath: storage.directory.path))
        viewing.cancel()
        await viewing.value
    }

    /// Saves one file in a directory, creating the directory.
    /// - Parameter directory: The directory to fill.
    /// - Throws: A filesystem error.
    private func createFile(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("saved".utf8).write(to: directory.appending(path: "file.json"))
    }

    /// Changes who can change a directory's contents.
    /// - Parameters:
    ///   - permissions: The POSIX permissions.
    ///   - directory: The directory to change.
    /// - Throws: A filesystem error.
    private func setPermissions(_ permissions: Int, of directory: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: directory.path)
    }
}
