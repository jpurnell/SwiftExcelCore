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
    /// A range is read no further than ``lastPopulatedCell()``. `$B:$B` is not a
    /// request for 1,048,576 cells; it is a request for whatever is in that column,
    /// and everything past the last one is empty by definition.
    ///
    /// - Parameter range: The cell range to read.
    /// - Returns: The rectangle.
    func matrix(in range: CellRange) -> CellMatrix

    /// Returns the values in a range of a named sheet, keeping the range's shape.
    ///
    /// A sheet that does not exist reads as blanks, matching what the flat read
    /// documented: an absent sheet is empty rather than an error.
    ///
    /// - Parameters:
    ///   - range: The cell range to read.
    ///   - inSheet: The name of the worksheet to read from.
    /// - Returns: The rectangle.
    func matrix(in range: CellRange, inSheet: String) -> CellMatrix

    /// The furthest cell the sheet holds anything at, or `nil` if unknown.
    ///
    /// This is what makes a whole-column reference affordable, and it is the only
    /// thing that can: a provider is the only party that knows where its data
    /// stops. `$B:$B` names 1,048,576 cells, and reading them all would allocate
    /// a rectangle a thousand times larger than the sheet.
    ///
    /// Only the far corner matters. Clipping the near one would shift every
    /// position in the result, and `INDEX($A:$A, 3)` means the third row of the
    /// sheet whether or not the first two hold anything.
    ///
    /// `nil` means the sheet holds **nothing**, so a range over it reads as an
    /// empty rectangle. It does not mean "I cannot say": a provider that genuinely
    /// does not know its bounds says so by naming the grid's own last cell,
    /// ``CellRef/lastOnSheet``, which clips nothing and takes every range at face
    /// value. Both states are real and they lead to opposite behaviour, so neither
    /// is left to be inferred from the other.
    ///
    /// - Returns: The last populated cell, or `nil` when the sheet is empty.
    func lastPopulatedCell() -> CellRef?

    /// The furthest cell a named sheet holds anything at, or `nil` if unknown.
    ///
    /// - Parameter inSheet: The name of the worksheet.
    /// - Returns: The last populated cell, or `nil` when that sheet is empty or
    ///   does not exist.
    func lastPopulatedCell(inSheet: String) -> CellRef?

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
    /// - Returns: The rectangle, clipped to the sheet's last populated cell.
    public func matrix(in range: CellRange) -> CellMatrix {
        read(range.clipped(to: lastPopulatedCell())) { value(at: $0) }
    }

    /// Reads a range of a named sheet cell by cell, keeping its shape.
    ///
    /// - Parameters:
    ///   - range: The cell range to read.
    ///   - inSheet: The name of the worksheet to read from.
    /// - Returns: The rectangle, clipped to that sheet's last populated cell.
    public func matrix(in range: CellRange, inSheet: String) -> CellMatrix {
        read(range.clipped(to: lastPopulatedCell(inSheet: inSheet))) {
            value(at: $0, inSheet: inSheet)
        }
    }

    /// Builds a rectangle from a lookup, one cell at a time.
    ///
    /// Walks rows and columns directly rather than through ``CellRange/cells``, so
    /// the references are never materialized as an array of their own — for a
    /// large range that array is the same size as the result and buys nothing.
    ///
    /// - Parameters:
    ///   - range: The already-clipped range to read.
    ///   - lookup: How to read one cell.
    /// - Returns: The rectangle, with absent cells as `.blank`.
    private func read(_ range: CellRange?, _ lookup: (CellRef) -> CellValue?) -> CellMatrix {
        guard let range else { return CellMatrix(row: []) }
        var elements: [CellValue] = []
        elements.reserveCapacity(range.rowCount * range.columnCount)
        for row in range.start.row...range.end.row {
            for column in range.start.column...range.end.column {
                elements.append(lookup(CellRef(column: column, row: row)) ?? .blank)
            }
        }
        return CellMatrix(elements: elements,
                          rows: range.rowCount,
                          columns: range.columnCount)
            ?? CellMatrix(row: [])
    }
}
