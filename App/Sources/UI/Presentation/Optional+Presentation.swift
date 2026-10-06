nonisolated extension Optional {
    /// Projects whether a value is present, so `$value[isPresented: true]` drives a presentation.
    ///
    /// Dismissing the presentation clears the value.
    /// - Parameter presented: The presence the binding reports as `true`.
    subscript(isPresented presented: Bool) -> Bool {
        get { (self != nil) == presented }
        set { if newValue != presented { self = nil } }
    }
}
