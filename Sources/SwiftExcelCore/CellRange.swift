/// A rectangular range of cells, e.g. `A1:B10`.
public struct CellRange: Equatable, Hashable, Sendable {
    /// The top-left cell of the range.
    public let start: CellRef
    /// The bottom-right cell of the range.
    public let end: CellRef

    /// Creates a range from two cell references.
    public init(from: CellRef, to: CellRef) {
        self.start = from
        self.end = to
    }

    /// Creates a range from two cell reference strings.
    public init(from: String, to: String) {
        self.start = CellRef(from)
        self.end = CellRef(to)
    }

    /// Parses a range string like `A1:B10` or a single cell like `A1`.
    public init(_ reference: String) {
        let parts = reference.split(separator: ":", maxSplits: 1)
        self.start = CellRef(String(parts[0]))
        self.end = parts.count > 1 ? CellRef(String(parts[1])) : CellRef(String(parts[0]))
    }

    /// The string representation, e.g. `A1:B10` or `A1` for single-cell ranges.
    public var reference: String {
        if start == end {
            return start.reference
        }
        return "\(start.reference):\(end.reference)"
    }

    /// Returns a copy with all cell references marked absolute.
    public func absolute() -> CellRange {
        CellRange(from: start.absolute(), to: end.absolute())
    }

    /// All cells in the range, iterated row by row.
    public var cells: [CellRef] {
        var result: [CellRef] = []
        result.reserveCapacity(rowCount * columnCount)
        for row in start.row...end.row {
            for col in start.column...end.column {
                result.append(CellRef(column: col, row: row))
            }
        }
        return result
    }

    /// Whether the range runs to the last row of the grid — `$B:$B`, which Excel
    /// writes as `B1:B1048576`.
    ///
    /// A structural test rather than a size test, and that is the whole point.
    /// Nothing can lie beyond the last row, so a range that reaches it was not
    /// describing a window with a chosen bottom edge; it was saying "to the end."
    /// `$B:$B` is not a request for a million cells, it is a request for whatever
    /// is in column B — which is what SwiftXLSX's dependency graph says of the
    /// same notation, in the same words.
    public var extendsToLastRow: Bool {
        end.row == CellRef.lastOnSheet.row
    }

    /// Whether the range runs to the last column of the grid — `$3:$3`, which Excel
    /// writes as `A3:XFD3`.
    public var extendsToLastColumn: Bool {
        end.column == CellRef.lastOnSheet.column
    }

    /// The range with its unbounded sides pulled back to where a sheet's data ends.
    ///
    /// Only the sides that span the whole grid are moved, and only their far
    /// corner. Two things follow, and both matter:
    ///
    /// A range the author actually wrote out is never touched. `A1:B3` stays three
    /// rows by two even on an empty sheet, because `COUNTBLANK(A1:B3)` is six and
    /// clipping it to the last populated cell would answer zero.
    ///
    /// The origin never moves. Positions are counted from where a range starts, so
    /// pulling the near corner in would renumber everything inside it —
    /// `INDEX($A:$A, 3)` means the third row of the sheet whether or not the first
    /// two hold anything.
    ///
    /// - Parameter limit: The furthest cell the sheet holds anything at, or `nil`
    ///   when it holds nothing at all.
    /// - Returns: The clipped range, or `nil` when an unbounded range meets an
    ///   empty sheet and there is nothing to read.
    public func clipped(to limit: CellRef?) -> CellRange? {
        guard extendsToLastRow || extendsToLastColumn else { return self }
        guard let limit else { return nil }
        guard limit.row >= start.row, limit.column >= start.column else { return nil }
        let lastRow = extendsToLastRow ? Swift.min(end.row, limit.row) : end.row
        let lastColumn = extendsToLastColumn
            ? Swift.min(end.column, limit.column)
            : end.column
        return CellRange(from: start, to: CellRef(column: lastColumn, row: lastRow))
    }

    /// The number of rows in the range.
    public var rowCount: Int {
        end.row - start.row + 1
    }

    /// The number of columns in the range.
    public var columnCount: Int {
        end.column - start.column + 1
    }
}
