/// A protocol for looking up cell values during formula evaluation.
///
/// Conforming types provide access to cell values by ``CellRef`` or ``CellRange``,
/// optionally scoped to a specific sheet name for cross-sheet references.
public protocol CellValueProvider: Sendable {
    /// Returns the value at the given cell reference in the current sheet.
    ///
    /// - Parameter ref: The cell reference to look up.
    /// - Returns: The cell value, or `nil` if the cell is empty.
    func value(at ref: CellRef) -> CellValue?

    /// Returns the value at the given cell reference in the specified sheet.
    ///
    /// - Parameters:
    ///   - ref: The cell reference to look up.
    ///   - inSheet: The name of the worksheet to search.
    /// - Returns: The cell value, or `nil` if the cell is empty or the sheet does not exist.
    func value(at ref: CellRef, inSheet: String) -> CellValue?

    /// Returns all non-nil values in the given cell range in the current sheet.
    ///
    /// - Parameter range: The cell range to enumerate.
    /// - Returns: An array of cell values, skipping empty cells.
    func values(in range: CellRange) -> [CellValue]

    /// Returns all non-nil values in the given cell range in the specified sheet.
    ///
    /// - Parameters:
    ///   - range: The cell range to enumerate.
    ///   - inSheet: The name of the worksheet to search.
    /// - Returns: An array of cell values, skipping empty cells. Returns an empty array if the sheet does not exist.
    func values(in range: CellRange, inSheet: String) -> [CellValue]
}
