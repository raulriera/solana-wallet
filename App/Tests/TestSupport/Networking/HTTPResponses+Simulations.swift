import Foundation

extension HTTPResponses {
    func simulations() throws -> Int {
        try requests.count { try $0.rpcMethod == "simulateTransaction" }
    }
}
