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

    /// The **source** field each data field summarises, parallel to ``dataFields``.
    ///
    /// `<dataField name="Sum of Subs" fld="11"/>` over cache field 11 gives the caption
    /// `Sum of Subs` and the source `Subs`, and **Excel answers to either**. The corpus needs
    /// the source: its formulas ask for `"Subs"`, never for `"Sum of Subs"`.
    ///
    /// Empty where the reader could not resolve the index to a name, which leaves the caption
    /// as the only way in rather than inventing one.
    public let dataFieldSources: [String]

    /// The row axis, outermost first — one rendered label column each, left to right.
    public let rowFields: [PivotAxisField]

    /// The column axis, outermost first.
    public let columnFields: [PivotAxisField]

    /// The page (filter) fields, in the order the file lists them.
    ///
    /// These are rendered **above** the table rather than inside it, which is why they are
    /// plain names: the `-2` pseudo-field never appears on this axis.
    public let pageFields: [String]

    /// How many rows of page fields are rendered above ``range``.
    ///
    /// `rowPageCount` in the file. The rows themselves are outside the declared location, so a
    /// reader that looks only inside the rectangle never sees the filters at all.
    public let pageFieldRowCount: Int

    /// The header row, counted from the top of ``range``.
    ///
    /// `firstHeaderRow` in the file, and **its own attribute** — not `firstDataRow - 1`. The
    /// two agree on every pivot measured so far, which is exactly the condition under which
    /// deriving one from the other survives until the first workbook where it does not.
    public let firstHeaderRow: Int

    /// Whether a grand total **row** is rendered at the bottom.
    ///
    /// Defaults to `true` in the file format — an absent `rowGrandTotals` attribute means
    /// present — which is why the reader must supply `true` rather than `false` when it finds
    /// nothing.
    public let hasRowGrandTotals: Bool

    /// Whether a grand total **column** is rendered at the right.
    public let hasColumnGrandTotals: Bool

    /// Records a pivot table's position, axes and column names.
    ///
    /// - Parameters:
    ///   - sheet: The sheet the table is rendered on.
    ///   - range: The rectangle it occupies, headers and totals included. Page fields are
    ///     rendered **above** this rectangle and are not part of it.
    ///   - firstHeaderRow: The header row, counted from the top of `range`. Read from
    ///     `firstHeaderRow` rather than derived from `firstDataRow`.
    ///   - firstDataRow: The first data row, counted from the top of `range`.
    ///   - firstDataCol: The first data column, counted from the left of `range`.
    ///   - dataFields: The data field captions, in the order the file lists them.
    ///   - dataFieldSources: The source field each summarises, parallel to `dataFields`.
    ///     Pass empty names where an index could not be resolved.
    ///   - rowFields: The row axis, outermost first.
    ///   - columnFields: The column axis, outermost first.
    ///   - pageFields: The page (filter) field names.
    ///   - pageFieldRowCount: How many rows of page fields are rendered above `range`.
    ///   - hasRowGrandTotals: Whether a grand total row is rendered at the bottom. The file
    ///     format defaults this to **true**, so a reader that finds no attribute passes
    ///     `true` rather than `false`.
    ///   - hasColumnGrandTotals: Whether a grand total column is rendered at the right,
    ///     defaulting the same way.
    public init(sheet: String, range: CellRange,
                firstHeaderRow: Int, firstDataRow: Int, firstDataCol: Int,
                dataFields: [String], dataFieldSources: [String],
                rowFields: [PivotAxisField], columnFields: [PivotAxisField],
                pageFields: [String], pageFieldRowCount: Int,
                hasRowGrandTotals: Bool, hasColumnGrandTotals: Bool) {
        self.sheet = sheet
        self.range = range
        self.firstHeaderRow = firstHeaderRow
        self.firstDataRow = firstDataRow
        self.firstDataCol = firstDataCol
        self.dataFields = dataFields
        self.dataFieldSources = dataFieldSources
        self.rowFields = rowFields
        self.columnFields = columnFields
        self.pageFields = pageFields
        self.pageFieldRowCount = pageFieldRowCount
        self.hasRowGrandTotals = hasRowGrandTotals
        self.hasColumnGrandTotals = hasColumnGrandTotals
    }

    /// Records a pivot table with no axis detail — position, captions and totals only.
    ///
    /// Enough for the two-argument `GETPIVOTDATA`, which needs a data field's column and the
    /// grand total row and nothing else. `firstHeaderRow` defaults to `firstDataRow - 1`,
    /// which is what this type derived before the attribute was read.
    ///
    /// - Parameters:
    ///   - sheet: The sheet the table is rendered on.
    ///   - range: The rectangle it occupies, headers and totals included.
    ///   - firstDataRow: The first data row, counted from the top of `range`.
    ///   - firstDataCol: The first data column, counted from the left of `range`.
    ///   - dataFields: The data field captions, in the order the file lists them.
    ///   - hasRowGrandTotals: Whether a grand total row is rendered at the bottom.
    ///   - hasColumnGrandTotals: Whether a grand total column is rendered at the right.
    public init(sheet: String, range: CellRange, firstDataRow: Int, firstDataCol: Int,
                dataFields: [String], hasRowGrandTotals: Bool, hasColumnGrandTotals: Bool) {
        self.init(sheet: sheet, range: range,
                  firstHeaderRow: firstDataRow - 1,
                  firstDataRow: firstDataRow, firstDataCol: firstDataCol,
                  dataFields: dataFields, dataFieldSources: [],
                  rowFields: [], columnFields: [], pageFields: [], pageFieldRowCount: 0,
                  hasRowGrandTotals: hasRowGrandTotals,
                  hasColumnGrandTotals: hasColumnGrandTotals)
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

    /// The row holding the row-field names and the column axis's items.
    ///
    /// `range.start.row + firstHeaderRow`. On the corpus fixture this is row 135, reading
    /// `Scenario | Region | LOBMix_noXH | BP/IP | 2014-01-21 | …`.
    public var headerRow: Int { range.start.row + firstHeaderRow }

    /// The row holding the data field caption and the column field's name.
    ///
    /// The top row of ``range``. It is the same row as ``headerRow`` only when
    /// ``firstHeaderRow`` is zero; on the corpus fixture it is row 134, reading
    /// `Sum of Subs` at the left and `FME_Calc` above the first data column.
    public var captionRow: Int { range.start.row }

    /// The first row of data on the sheet.
    public var firstDataSheetRow: Int { range.start.row + firstDataRow }

    /// The first column of data on the sheet.
    ///
    /// Everything left of it within ``range`` is row labels, one column per row field.
    public var firstDataSheetColumn: Int { range.start.column + firstDataCol }

    /// The columns holding data, left to right.
    public var dataColumns: ClosedRange<Int> {
        let first = firstDataSheetColumn
        return first...Swift.max(first, range.end.column)
    }

    /// The rows of page fields rendered above ``range``, in the order ``pageFields`` lists them.
    ///
    /// Page fields are **outside** the declared location, and **one blank row separates them
    /// from the table**. `rowPageCount="2"` against a range starting at row 134 puts them on
    /// rows 131 and 132, leaving 133 empty — so the topmost is
    /// `range.start.row - pageFieldRowCount - 1` and not `range.start.row - 1`.
    ///
    /// Measured across all 40 pivots in `Dot Com YTD Performance Report 6 20.xlsx` that carry
    /// page fields: every one of them, at both `rowPageCount` 1 and 2, and every one rendered
    /// top to bottom in listing order. The separator row is not optional in this evidence, and
    /// assuming it away put the reader one row high on all 40.
    public var pageFieldRows: [Int] {
        guard pageFieldRowCount > 0 else { return [] }
        let top = range.start.row - pageFieldRowCount - 1
        guard top > 0 else { return [] }
        return (0..<pageFieldRowCount).map { top + $0 }
    }

    /// The column rendering a row field's labels, or `nil` where the field is not on the row
    /// axis.
    ///
    /// One column per row field, left to right in the order the file lists them — so the
    /// outermost field is leftmost, which is also the order subtotals nest in.
    ///
    /// - Parameter field: The field to locate.
    /// - Returns: The sheet column holding its labels.
    public func labelColumn(of field: PivotAxisField) -> Int? {
        let index: Int?
        switch field {
        case .dataFieldNames:
            index = rowFields.firstIndex(of: .dataFieldNames)
        case .field(let name):
            index = rowFields.firstIndex { $0.matches(name) }
        }
        guard let index, index < firstDataCol else { return nil }
        return range.start.column + index
    }

    /// The data field a formula's first argument names, by caption **or** by source field.
    ///
    /// Excel accepts either, and the corpus needs the source: its formulas ask for `"Subs"`
    /// against a caption of `"Sum of Subs"`. Matched case-insensitively and **never trimmed**
    /// — three captions in the corpus workbook are written with a leading space.
    ///
    /// - Parameter name: The name a formula wrote.
    /// - Returns: The field's position in ``dataFields``, or `nil` where it names none.
    public func dataFieldIndex(named name: String) -> Int? {
        let wanted = name.lowercased()
        if let index = dataFields.firstIndex(where: { $0.lowercased() == wanted }) {
            return index
        }
        guard let index = dataFieldSources.firstIndex(where: { $0.lowercased() == wanted }),
              index < dataFields.count else {
            return nil
        }
        return index
    }

    /// The grand total row, when the table renders one.
    ///
    /// The last row of ``range``, and `nil` where ``hasRowGrandTotals`` is not set. Found this
    /// way rather than by label — see the note on the type.
    public var grandTotalRow: Int? {
        hasRowGrandTotals ? range.end.row : nil
    }
}
