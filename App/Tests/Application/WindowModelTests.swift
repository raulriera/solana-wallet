import SwiftUI
import Testing
@testable import widgets

/// Verifies the window's account, which the saved accounts give, and the binding that Settings changes it through.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowModelTests {
    /// A reset removes the wallet while its screens still read the account's binding.
    /// - Throws: A test prerequisite error.
    @Test
    func `Leaving the wallet closes its screens without losing their account`() async throws {
        let account = try Account.fixture(index: 1)
        let accounts = AccountStore.inMemory(StoredValue([account]))
        let window = await makeWindow(over: accounts)
        let closed = AsyncStream<Void>.makeStream()
        let hosted = try HostedWindow(WindowAccountRoot(window: window, closed: closed.continuation))
        defer {
            hosted.close()
            closed.continuation.finish()
        }
        try #require(try await hosted.appears())

        try await accounts.erase()

        // The suite's time limit ends the wait if the screens never close.
        var closes = closed.stream.makeAsyncIterator()
        #expect(await closes.next() != nil)
    }

    /// Choosing another account in Settings shows it in the window, and another window keeps its own.
    /// - Throws: A test prerequisite error.
    @Test
    func `Choosing another account shows it in the window only`() async throws {
        let first = try Account.fixture(index: 1)
        let second = try Account.fixture(index: 2, recoveryID: first.recoveryID)
        let accounts = AccountStore.inMemory(StoredValue([first, second]))
        let window = await makeWindow(over: accounts)
        let otherWindow = await makeWindow(over: accounts)

        window[account: first] = second

        #expect(window.destination == .wallet(second))
        #expect(otherWindow.destination == .wallet(first))
    }

    /// Another window's rename shows at once, without changing the destination's identity.
    /// - Throws: A test prerequisite error.
    @Test
    func `A renamed account shows at once`() async throws {
        let account = try Account.fixture(index: 1)
        let accounts = AccountStore.inMemory(StoredValue([account]))
        let window = await makeWindow(over: accounts)
        let identity = window.destination.id

        try await accounts.rename(account.id, to: "Savings")

        #expect(window.account?.name == "Savings")
        #expect(window.destination.id == identity)
    }

    /// Creates a window over the saved accounts and runs its startup, which opens the first saved account.
    /// - Parameter accounts: The saved accounts.
    /// - Returns: The window's navigation.
    private func makeWindow(over accounts: AccountStore) async -> WindowModel {
        let window = WindowModel(accounts: accounts)
        await window.restore(preferring: nil)
        return window
    }
}

/// Shows the account list while the window shows a wallet, as the window's root does with Settings, and reports when
/// the list closes.
private struct WindowAccountRoot: View {
    @State private var addition = AccountAdditionModel()
    @State private var deletion = AccountDeletionModel()
    @Bindable var window: WindowModel
    let closed: AsyncStream<Void>.Continuation

    var body: some View {
        ZStack {
            if case .wallet(let account) = window.destination {
                NavigationStack {
                    AccountsScreen(accounts: [account], selection: $window[account: account], addition: addition,
                                   deletion: deletion, path: .constant([]))
                }
                .onDisappear { closed.yield() }
            }
        }
        .animation(.default, value: window.destination)
    }
}
