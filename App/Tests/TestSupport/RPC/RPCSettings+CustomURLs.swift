import Foundation
@testable import widgets

extension RPCSettings {
    init(selection: Provider = .solana, customRPCs urls: [URL]) {
        self.init(selection: selection, customRPCs: urls.map { CustomRPC(url: $0, capabilities: []) })
    }
}
