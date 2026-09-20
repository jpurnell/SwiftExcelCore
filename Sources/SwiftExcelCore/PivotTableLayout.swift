import Foundation

/// Where a pivot table sits on a sheet, and what its columns are called.
///
/// ## What this is, and what it deliberately is not
///
/// **`GETPIVOTDATA` reads a rendered table.** A pivot table's values are written onto the
/// worksheet and cached there like any other cell, so the function is a lookup rather than a
/// recomputation — it never aggregates, and `xl/pivotCache/` is never opened. One corpus
/// workbook carries 76 cache parts and needs none of them.
///
/// So this type carries **no values**. It says where the table is and what its data fields are
/// called; the values are read back through a ``CellValueProvider`` from the sheet, which is
/// the entire point.
///
/// ## Why the grand total is found structurally
///
/// The grand total is the **last row of ``range``** when ``hasRowGrandTotals`` is set, and
/// there is none when it is not. It is emphatically *not* found by looking for a row labelled
/// `"Grand Total"`.
///
/// That was measured rather than assumed. `Dot Com YTD Performance Report 6 20.xlsx` carries
/// pivots both ways, and the one with `rowGrandTotals="0"` ends on a row reading
/// **`"KEY Total"`** — a *subtotal*. A label match for `"…Total"` would have taken it for a
/// grand total and returned the wrong number, quietly. Reading no labels at all avoids that
/// and avoids the locale trap together: the same label is `"Gesamtergebnis"` in German, and a
/// rule that works on an English corpus and fails on the first German workbook is the kind
/// that ships.
public struct PivotTableLayout: Equatable, Hashable, Sendable {

    /// The sheet the table is rendered on.
    public let sheet: String

    /// The rectangle it occupies, headers and totals included.
    public let range: CellRange

    /// The first row of data, counted from the top of ``range``.
    ///
    /// `1` where a single header row precedes the data, which is the ordinary case.
    public let firstDataRow: Int

    /// The first column of data, counted from the left of ``range``.
    ///
    /// `1` where one column of row labels precedes the data.
    public let firstDataCol: Int

    /// The data fields, in the order the file lists them.
    ///
    /// Each name is also the text written into that field's column header on the sheet, which
    /// is how `GETPIVOTDATA` finds the column: it is given the name and has to find the
    /// column, and the header row is where the two meet.
    public let dataFields: [String]

    /// Whether a grand total **row** is rendered at the bottom.
    ///
    /// Defaults to `true` in the file format — an absent `rowGrandTotals` attribute means
    /// present — which is why the reader must supply `true` rather than `false` when it finds
    /// nothing.
    public let hasRowGrandTotals: Bool

    /// Whether a grand total **column** is rendered at the right.
    public let hasColumnGrandTotals: Bool

    /// Records a pivot table's position and column names.
    ///
    /// - Parameters:
    ///   - sheet: The sheet the table is rendered on.
    ///   - range: The rectangle it occupies, headers and totals included.
    ///   - firstDataRow: The first data row, counted from the top of `range`.
    ///   - firstDataCol: The first data column, counted from the left of `range`.
    ///   - dataFields: The data field names, in the order the file lists them.
    ///   - hasRowGrandTotals: Whether a grand total row is rendered at the bottom. The file
    ///     format defaults this to **true**, so a reader that finds no attribute passes
    ///     `true` rather than `false`.
    ///   - hasColumnGrandTotals: Whether a grand total column is rendered at the right,
    ///     defaulting the same way.
    public init(sheet: String, range: CellRange, firstDataRow: Int, firstDataCol: Int,
                dataFields: [String], hasRowGrandTotals: Bool, hasColumnGrandTotals: Bool) {
        self.sheet = sheet
        self.range = range
        self.firstDataRow = firstDataRow
        self.firstDataCol = firstDataCol
        self.dataFields = dataFields
        self.hasRowGrandTotals = hasRowGrandTotals
        self.hasColumnGrandTotals = hasColumnGrandTotals
    }

    /// Whether a cell falls inside this table.
    ///
    /// `GETPIVOTDATA`'s second argument is *any* cell of the table and exists only to say
    /// which table is meant, so containment is the whole test.
    ///
    /// - Parameter cell: The cell to test.
    /// - Returns: `true` where it sits within ``range``.
    public func contains(_ cell: CellRef) -> Bool {
        cell.row >= range.start.row && cell.row <= range.end.row
            && cell.column >= range.start.column && cell.column <= range.end.column
    }

    /// The row where the header text for each data field is written.
    ///
    /// The row immediately above the first data row, which is where the reader will look for
    /// a field's name to find its column.
    public var headerRow: Int { range.start.row + firstDataRow - 1 }

    /// The grand total row, when the table renders one.
    ///
    /// The last row of ``range``, and `nil` where ``hasRowGrandTotals`` is not set. Found this
    /// way rather than by label — see the note on the type.
    public var grandTotalRow: Int? {
        hasRowGrandTotals ? range.end.row : nil
    }
}
