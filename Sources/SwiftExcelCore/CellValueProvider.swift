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

    /// Returns the values in a range, keeping the range's shape.
    ///
    /// Empty cells read as ``CellValue/blank`` at their own position rather than
    /// closing the gap, which is what makes positional access — `INDEX`, the
    /// lookups, `TRANSPOSE` — mean anything.
    ///
    /// A default implementation derives this from ``value(at:)``, so a conforming
    /// type gets a correct shaped read without writing one. Override it only to
    /// read a block more directly than cell by cell.
    ///
    /// - Parameter range: The cell range to read.
    /// - Returns: The rectangle, or `nil` if the range holds more than
    ///   ``CellMatrix/maximumCells`` cells and was refused.
    func matrix(in range: CellRange) -> CellMatrix?

    /// Returns the values in a range of a named sheet, keeping the range's shape.
    ///
    /// A sheet that does not exist reads as blanks, matching what the flat read
    /// documented: an absent sheet is empty rather than an error.
    ///
    /// - Parameters:
    ///   - range: The cell range to read.
    ///   - inSheet: The name of the worksheet to read from.
    /// - Returns: The rectangle, or `nil` if the range was refused as too large.
    func matrix(in range: CellRange, inSheet: String) -> CellMatrix?

    /// Returns all non-nil values in the given cell range in the current sheet.
    ///
    /// - Parameter range: The cell range to enumerate.
    /// - Returns: An array of cell values, skipping empty cells.
    @available(*, deprecated, message: "Use matrix(in:), which keeps shape and blanks.")
    func values(in range: CellRange) -> [CellValue]

    /// Returns all non-nil values in the given cell range in the specified sheet.
    ///
    /// - Parameters:
    ///   - range: The cell range to enumerate.
    ///   - inSheet: The name of the worksheet to search.
    /// - Returns: An array of cell values, skipping empty cells. Returns an empty array if the sheet does not exist.
    @available(*, deprecated, message: "Use matrix(in:inSheet:), which keeps shape and blanks.")
    func values(in range: CellRange, inSheet: String) -> [CellValue]
}

extension CellValueProvider {

    /// Reads a range cell by cell, keeping its shape.
    ///
    /// Derived from ``value(at:)``, which every conforming type already has, and
    /// from ``CellRange/cells`` — whose row-major order is the same order
    /// ``CellMatrix`` indexes in, so the two agree by construction rather than by
    /// agreement.
    ///
    /// - Parameter range: The cell range to read.
    /// - Returns: The rectangle, or `nil` when refused as too large.
    public func matrix(in range: CellRange) -> CellMatrix? {
        guard range.rowCount * range.columnCount <= CellMatrix.maximumCells else { return nil }
        let elements = range.cells.map { value(at: $0) ?? .blank }
        return CellMatrix(elements: elements,
                          rows: range.rowCount,
                          columns: range.columnCount)
    }

    /// Reads a range of a named sheet cell by cell, keeping its shape.
    ///
    /// - Parameters:
    ///   - range: The cell range to read.
    ///   - inSheet: The name of the worksheet to read from.
    /// - Returns: The rectangle, or `nil` when refused as too large.
    public func matrix(in range: CellRange, inSheet: String) -> CellMatrix? {
        guard range.rowCount * range.columnCount <= CellMatrix.maximumCells else { return nil }
        let elements = range.cells.map { value(at: $0, inSheet: inSheet) ?? .blank }
        return CellMatrix(elements: elements,
                          rows: range.rowCount,
                          columns: range.columnCount)
    }
}
