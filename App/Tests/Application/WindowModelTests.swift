import SwiftUI
import Testing
@testable import widgets

/// Verifies the window's account and the binding that Settings changes it through.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowModelTests {
    /// A reset removes the wallet while its screens still read the account's binding.
    /// - Throws: A test prerequisite error.
    @Test
    func `Leaving the wallet closes its screens without losing their account`() async throws {
        let account = try Account.fixture(index: 1)
        let window = makeWindow(showing: account)
        let closed = AsyncStream<Void>.makeStream()
        let hosted = try HostedWindow(WindowAccountRoot(window: window, closed: closed.continuation))
        defer {
            hosted.close()
            closed.continuation.finish()
        }
        try #require(try await hosted.appears())

        window.router.route(to: .onboarding)

        // The suite's time limit ends the wait if the screens never close.
        var closes = closed.stream.makeAsyncIterator()
        #expect(await closes.next() != nil)
    }

    /// Choosing another account in Settings shows it in the window.
    /// - Throws: A test prerequisite error.
    @Test
    func `Choosing another account shows it in the window`() throws {
        let first = try Account.fixture(index: 1)
        let second = try Account.fixture(index: 2, recoveryID: first.recoveryID)
        let window = makeWindow(showing: first)

        window[account: first] = second

        #expect(window.router.destination == .wallet(second))
    }

    /// Creates a window that shows an account and restores nothing.
    /// - Parameter account: The account that the window shows.
    /// - Returns: The window's navigation.
    private func makeWindow(showing account: Account) -> WindowModel {
        let router = WindowRouter(initialDestination: .wallet(account))
        return WindowModel(router: router, startup: WindowStartup(accounts: .inMemory(), router: router))
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
            if case .wallet(let account) = window.router.destination {
                NavigationStack {
                    AccountsScreen(accounts: [account], selection: $window[account: account], addition: addition,
                                   deletion: deletion, path: .constant([]))
                }
                .onDisappear { closed.yield() }
            }
        }
        .animation(.default, value: window.router.destination)
    }
}
