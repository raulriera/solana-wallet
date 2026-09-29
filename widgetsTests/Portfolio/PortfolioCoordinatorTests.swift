import Foundation
import Observation
import Portfolio
import RPC
import Testing
@testable import widgets

/// Exercises the view lifetime separately from the framework's network behavior.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PortfolioCoordinatorTests {
    /// Verifies an inactive scene or missing selection never starts work.
    @Test("inactive and unselected portfolios do not request data", arguments: [false, true])
    func inactiveDoesNotRequestData(isActive: Bool) async {
        let service = PortfolioResponses()
        let coordinator: any PortfolioCoordinating = PortfolioCoordinator(service: service)
        await coordinator.observe(for: isActive ? nil : "wallet-a", isActive: isActive)
        await coordinator.refresh()
        #expect(coordinator.update == nil)
        #expect(await service.calls.isEmpty)
    }

    /// Verifies backgrounding retains holdings, cancels both operations, and reopening observes again.
    @Test("background stops work and foreground reopens the selected wallet")
    func backgroundStopsAndForegroundRestarts() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        #expect(observation.kind == .observation)
        let cached = snapshot(owner: "wallet-a", revision: 1)
        observation.continuation.yield(Update(snapshot: cached, phase: .ready))
        await waitForSnapshot(cached, in: coordinator)

        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())
        reload.continuation.yield(Update(snapshot: cached, phase: .refreshing))
        await waitForProgress(in: coordinator)

        await coordinator.observe(for: "wallet-a", isActive: false)
        await viewing.value
        await refreshing.value
        for await _ in observation.termination {}
        for await _ in reload.termination {}
        #expect(coordinator.update?.snapshot == cached)
        #expect(coordinator.update?.isRefreshing == false)
        await coordinator.refresh()
        #expect(await service.calls.count == 2)

        let reopened = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { reopened.cancel() }
        let resumed = try #require(await requests.next())
        #expect(resumed.owner == "wallet-a")
        #expect(resumed.kind == .observation)
        #expect(coordinator.update?.snapshot == cached)
        reopened.cancel()
        await reopened.value
    }

    /// Verifies selection changes clear old holdings and obsolete cleanup cannot stop the replacement.
    @Test("switching wallets clears displayed data and cancels old work")
    func switchingWalletsClearsOldState() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let first = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { first.cancel() }
        let old = try #require(await requests.next())
        let cached = snapshot(owner: "wallet-a", revision: 1)
        old.continuation.yield(Update(snapshot: cached, phase: .ready))
        await waitForSnapshot(cached, in: coordinator)
        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())

        let second = Task { await coordinator.observe(for: "wallet-b", isActive: true) }
        defer { second.cancel() }
        let current = try #require(await requests.next())
        #expect(coordinator.update == nil)
        await first.value
        await refreshing.value
        for await _ in old.termination {}
        for await _ in reload.termination {}
        old.continuation.yield(Update(snapshot: cached, phase: .ready))
        reload.continuation.yield(Update(snapshot: cached, phase: .ready))
        let replacement = snapshot(owner: "wallet-b", revision: 2)
        current.continuation.yield(Update(snapshot: replacement, phase: .ready))
        await waitForSnapshot(replacement, in: coordinator)
        second.cancel()
        await second.value
        #expect(coordinator.update?.snapshot == replacement)

        await coordinator.observe(for: nil, isActive: true)
        #expect(coordinator.update == nil)
    }

    /// Verifies a cancelled provider setup cannot deliver buffered data or stop a newer session.
    @Test("late registration from a cancelled session cannot publish")
    func lateRegistrationCannotPublish() async throws {
        let gate = PortfolioResponses.Registration()
        let service = PortfolioResponses(registration: gate)
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let first = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { first.cancel() }
        let old = try #require(await requests.next())
        old.continuation.yield(Update(snapshot: snapshot(owner: "wallet-a", revision: 99), phase: .ready))

        let second = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { second.cancel() }
        let current = try #require(await requests.next())
        let expected = snapshot(owner: "wallet-a", revision: 2)
        current.continuation.yield(Update(snapshot: expected, phase: .ready))
        await gate.release()
        await first.value
        await waitForSnapshot(expected, in: coordinator)
        second.cancel()
        await second.value
        #expect(coordinator.update?.snapshot == expected)
    }

    /// Verifies view task cancellation ends observation and permits coordinator deallocation.
    @Test("view cancellation releases observation and presentation state")
    func viewCancellationReleasesCoordinator() async throws {
        let service = PortfolioResponses()
        var coordinator: PortfolioCoordinator? = PortfolioCoordinator(service: service)
        weak let released = coordinator
        var requests = service.requests.makeAsyncIterator()
        var viewing: Task<Void, Never>? = Task { [coordinator] in
            await coordinator?.observe(for: "wallet-a", isActive: true)
        }
        let observation = try #require(await requests.next())
        viewing?.cancel()
        await viewing?.value
        for await _ in observation.termination {}
        viewing = nil
        coordinator = nil
        #expect(released == nil)
    }

    /// Verifies pull-to-refresh awaits a forced reload and observation remains usable afterward.
    @Test("pull to refresh forces a reload and preserves observation")
    func manualRefreshUsesReload() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())
        #expect(reload.owner == "wallet-a")
        #expect(reload.kind == .refresh(.reload))
        let refreshed = snapshot(owner: "wallet-a", revision: 2)
        reload.continuation.yield(Update(snapshot: refreshed, phase: .ready))
        reload.continuation.finish()
        await refreshing.value
        #expect(coordinator.update?.snapshot == refreshed)

        let changed = snapshot(owner: "wallet-a", revision: 3)
        observation.continuation.yield(Update(snapshot: changed, phase: .ready))
        await waitForSnapshot(changed, in: coordinator)
        viewing.cancel()
        await viewing.value
        #expect(await service.calls.count == 2)
    }

    /// Verifies cancelling a manual refresh does not cancel confirmed-change observation.
    @Test("cancelling pull to refresh leaves observation active")
    func cancellingRefreshKeepsObservation() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let refreshing = Task { await coordinator.refresh() }
        let reload = try #require(await requests.next())
        reload.continuation.yield(Update(snapshot: nil, phase: .refreshing))
        await waitForProgress(in: coordinator)
        refreshing.cancel()
        await refreshing.value
        for await _ in reload.termination {}
        #expect(coordinator.update == nil)

        let changed = snapshot(owner: "wallet-a", revision: 3)
        observation.continuation.yield(Update(snapshot: changed, phase: .ready))
        await waitForSnapshot(changed, in: coordinator)
        viewing.cancel()
        await viewing.value
    }

    /// Verifies repeated gestures share work and cancellation preserves observation's own progress.
    @Test("overlapping manual refreshes share one request")
    func overlappingRefreshesShareRequest() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let cached = snapshot(owner: "wallet-a", revision: 1)
        observation.continuation.yield(Update(snapshot: cached, phase: .refreshing))
        await waitForProgress(in: coordinator)
        let first = Task { await coordinator.refresh() }
        defer { first.cancel() }
        let reload = try #require(await requests.next())
        let joined = AsyncStream<Void>.makeStream()
        let second = Task {
            // The main-actor refresh registers synchronously before suspending;
            // the test cannot resume until that registration has completed.
            joined.continuation.finish()
            await coordinator.refresh()
        }
        defer { second.cancel() }
        for await _ in joined.stream {}
        #expect(await service.calls.count == 2)
        first.cancel()
        await first.value
        await second.value
        for await _ in reload.termination {}
        #expect(coordinator.update?.isRefreshing == true)

        observation.continuation.yield(Update(snapshot: cached, phase: .ready))
        viewing.cancel()
        await viewing.value
        #expect(coordinator.update?.snapshot == cached)
        #expect(coordinator.update?.isRefreshing == false)
    }

    /// Verifies a disconnection preserves holdings and allows explicit reload without reconnecting.
    @Test("subscription failure preserves data and allows manual refresh")
    func disconnectedObservationAllowsRefresh() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let cached = snapshot(owner: "wallet-a", revision: 1)
        let error = RPCError.http(statusCode: 429, retryAfter: "3")
        observation.continuation.yield(Update(snapshot: cached, phase: .failed(error)))
        observation.continuation.finish()
        await waitForSnapshot(cached, in: coordinator)
        #expect(coordinator.update?.error as? RPCError == error)

        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())
        #expect(reload.kind == .refresh(.reload))
        reload.continuation.yield(Update(snapshot: cached, phase: .ready))
        reload.continuation.finish()
        await refreshing.value
        #expect(coordinator.update?.error == nil)
        #expect(await service.calls.count == 2)
        viewing.cancel()
        await viewing.value
    }

    /// Verifies independently queued streams cannot replace newer holdings with an older snapshot.
    @Test("late refresh errors retain the newest observed holdings")
    func olderResultsPreserveNewerHoldings() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())
        let recent = snapshot(owner: "wallet-a", revision: 3)
        observation.continuation.yield(Update(snapshot: recent, phase: .ready))
        await waitForSnapshot(recent, in: coordinator)
        let error = RPCError.http(statusCode: 429, retryAfter: nil)
        reload.continuation.yield(Update(snapshot: snapshot(owner: "wallet-a", revision: 1), phase: .failed(error)))
        reload.continuation.finish()
        await refreshing.value
        #expect(coordinator.update?.snapshot == recent)
        #expect(coordinator.update?.error as? RPCError == error)
        viewing.cancel()
        await viewing.value
    }

    /// Creates distinct complete results without wallet recovery or live addresses.
    /// - Parameters:
    ///   - owner: The test wallet's label.
    ///   - revision: A deterministic retrieval time.
    /// - Returns: A valid empty fungible portfolio.
    private func snapshot(owner: String, revision: TimeInterval) -> Snapshot {
        Snapshot(owner: owner, network: .devnet, holdings: [], fetchedAt: Date(timeIntervalSince1970: revision),
                 lastIndexedSlot: nil)
    }

    /// Awaits observable snapshot publication without sleeps or polling.
    /// - Parameters:
    ///   - expected: The snapshot that must reach presentation state.
    ///   - coordinator: The presentation under test.
    private func waitForSnapshot(_ expected: Snapshot, in coordinator: PortfolioCoordinator) async {
        for await snapshot in Observations({ coordinator.update?.snapshot }) {
            if snapshot == expected { return }
        }
    }

    /// Awaits observable progress before exercising cancellation.
    /// - Parameter coordinator: The presentation under test.
    private func waitForProgress(in coordinator: PortfolioCoordinator) async {
        for await refreshing in Observations({ coordinator.update?.isRefreshing == true }) {
            if refreshing { return }
        }
    }
}
