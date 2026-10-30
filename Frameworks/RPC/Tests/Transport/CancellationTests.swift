import Foundation
import Testing
@testable import RPC

struct CancellationTests {
    @Test(arguments: [CancellationError(), URLError(.cancelled)] as [any Error])
    func `Cancellation errors and cancelled URL requests mean cancellation`(_ error: any Error) {
        #expect(error.isCancellation)
    }

    @Test(arguments: [URLError(.timedOut), RPCError.decoding] as [any Error])
    func `Other failures in a running task don't mean cancellation`(_ error: any Error) {
        #expect(!error.isCancellation)
    }

    @Test
    func `Any failure in a cancelled task means cancellation`() async {
        let isCancellation = await withTaskGroup(of: Bool.self) { group in
            group.cancelAll()
            group.addTask { URLError(.timedOut).isCancellation }
            return await group.next() ?? false
        }

        #expect(isCancellation)
    }
}
