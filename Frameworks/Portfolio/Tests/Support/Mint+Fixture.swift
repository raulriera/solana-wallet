@testable import Transactions

// swift-format-ignore: NeverUseForceTry
extension Mint {
    static func fixture(_ address: String, program: TokenProgram = .token, decimals: UInt8, name: String? = nil,
                        symbol: String? = nil) -> Mint {
        let metadata = name == nil && symbol == nil ? nil : TokenMetadata(name: name, symbol: symbol)
        return Mint(address: try! Address(address), program: program, decimals: decimals, metadata: metadata)
    }
}
