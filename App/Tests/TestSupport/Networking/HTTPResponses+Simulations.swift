import Foundation

extension HTTPResponses {
    /// Counts the simulations sent so far.
    /// - Returns: The number of `simulateTransaction` requests.
    /// - Throws: A test prerequisite error for a request without a method.
    func simulations() throws -> Int {
        try requests.count { try $0.rpcMethod == "simulateTransaction" }
    }
}
