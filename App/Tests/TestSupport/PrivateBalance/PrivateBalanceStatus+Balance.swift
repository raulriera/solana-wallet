@testable import widgets

extension PrivateBalanceStatus {
    static func balance(available: UInt64, pending: UInt64, of asset: PrivateAsset = .sol) -> PrivateBalanceStatus {
        .balance(Balances([asset: Balance(available: available, pending: pending)]))
    }
}
