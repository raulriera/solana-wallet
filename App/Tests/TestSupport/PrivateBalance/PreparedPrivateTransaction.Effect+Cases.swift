import Privacy
@testable import widgets

extension PreparedPrivateTransaction.Effect {
    var spend: PrivateSpend? {
        if case .spend(let spend) = self { spend } else { nil }
    }

    var codeCreation: (spend: PrivateSpend, index: UInt32, reserve: UInt64)? {
        if case .createCode(let spend, let index, let reserve) = self { (spend, index, reserve) } else { nil }
    }

    var redemption: Redemption? {
        if case .redeem(let redemption) = self { redemption } else { nil }
    }
}
