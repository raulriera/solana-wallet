import Foundation
import Synchronization

final class HeldFilePresenter: NSObject, NSFilePresenter, Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    let requested = AsyncStream<Void>.makeStream()
    private let state = Mutex(State())

    private struct State {
        var released = false
        var callbacks: [@Sendable ((any Error)?) -> Void] = []
    }

    init(url: URL) {
        presentedItemURL = url
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    func savePresentedItemChanges(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        hold(completionHandler)
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        hold(completionHandler)
    }

    func release() {
        let callbacks = state.withLock { state in
            state.released = true
            let callbacks = state.callbacks
            state.callbacks.removeAll()
            return callbacks
        }
        for callback in callbacks { callback(nil) }
    }

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
