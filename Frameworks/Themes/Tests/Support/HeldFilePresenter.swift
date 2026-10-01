import Foundation
import Synchronization

/// Holds real file coordination at a presenter callback until the test releases it.
final class HeldFilePresenter: NSObject, NSFilePresenter, Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    let requested = AsyncStream<Void>.makeStream()
    private let state = Mutex(State())

    private struct State {
        var released = false
        var callbacks: [@Sendable ((any Error)?) -> Void] = []
    }

    /// Creates a presenter whose callbacks run independently of Swift's executor.
    /// - Parameter url: The unique fixture package being coordinated.
    init(url: URL) {
        presentedItemURL = url
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    /// Delays a read or ordinary write until the test releases the presenter.
    /// - Parameter completionHandler: Foundation's pending save acknowledgement.
    func savePresentedItemChanges(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        hold(completionHandler)
    }

    /// Delays replacement exports at their deletion acknowledgement.
    /// - Parameter completionHandler: Foundation's pending replacement acknowledgement.
    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        hold(completionHandler)
    }

    /// Releases pending and future coordination callbacks without holding the state lock.
    func release() {
        let callbacks = state.withLock { state in
            state.released = true
            let callbacks = state.callbacks
            state.callbacks.removeAll()
            return callbacks
        }
        for callback in callbacks { callback(nil) }
    }

    /// Records a blocked coordination request or acknowledges an already released presenter.
    /// - Parameter callback: The system acknowledgement to retain temporarily.
    private func hold(_ callback: @escaping @Sendable ((any Error)?) -> Void) {
        let released = state.withLock { state in
            if state.released { return true }
            state.callbacks.append(callback)
            return false
        }
        requested.continuation.yield(())
        requested.continuation.finish()
        if released { callback(nil) }
    }
}
