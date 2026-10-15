import Foundation
import Testing
@testable import RPC

/// Verifies which failures count as cancellation.
struct CancellationTests {
    /// Verifies that Swift's cancellation error and URL loading's cancelled code both mean cancellation.
    ///
    /// - Parameter error: A failure that reports cancellation.
    @Test(arguments: [CancellationError(), URLError(.cancelled)] as [any Error])
    func `Cancellation errors and cancelled URL requests mean cancellation`(_ error: any Error) {
        #expect(error.isCancellation)
    }

    /// Verifies that other failures in a running task don't mean cancellation.
    ///
    /// - Parameter error: A failure unrelated to cancellation.
    @Test(arguments: [URLError(.timedOut), RPCError.decoding] as [any Error])
    func `Other failures in a running task don't mean cancellation`(_ error: any Error) {
        #expect(!error.isCancellation)
    }

    /// Verifies that any failure means cancellation once its task is cancelled.
    @Test
    func `Any failure in a cancelled task means cancellation`() async {
        let isCancellation = await withTaskGroup(of: Bool.self) { group in
            // A task added after the group is cancelled starts cancelled.
            group.cancelAll()
            group.addTask { URLError(.timedOut).isCancellation }
            return await group.next() ?? false
        }

        #expect(isCancellation)
    }
}
