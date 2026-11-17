extension Sequence where Element: FixedWidthInteger {
    /// Returns the sum of the elements, along with a Boolean value that indicates whether overflow occurred in the
    /// addition.
    ///
    /// - Returns: The sum, truncated after an overflow, and whether an overflow occurred.
    func sumReportingOverflow() -> (partialValue: Element, overflow: Bool) {
        reduce((partialValue: 0, overflow: false)) { total, element in
            let (sum, overflow) = total.partialValue.addingReportingOverflow(element)
            return (sum, total.overflow || overflow)
        }
    }
}
