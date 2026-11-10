import SwiftUI

@MainActor
final class BindingSource<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }

    var binding: Binding<Value> {
        Binding { self.value } set: { self.value = $0 }
    }
}
