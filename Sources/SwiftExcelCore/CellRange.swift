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

    /// Parses a range string like `A1:B10`, a single cell like `A1`, or a whole span
    /// like `A:A`, `$D:$D`, `1:1` or `2:5`.
    ///
    /// ## The whole-span forms, and what this used to do with them
    ///
    /// Each half went to ``CellRef/init(_:)``, which defaults a missing row to 1 and a
    /// missing column to 0. So `A:A` came back as the single cell `A1`, `A:C` as a plausible
    /// 1×3, and — worse — `1:1` and `2:5` as ranges in **column zero**, which is not a
    /// column: they are 1-based. `CellRange("2:5").rowCount` answered 4 while every
    /// reference it enumerated was off the grid, so the count looked right and the cells
    /// were unusable.
    ///
    /// A whole span is now recognised: a column span runs to the last row, a row span to the
    /// last column, and the `$` markers are carried so a writer can put back what it read.
    ///
    /// ## Order is normalised
    ///
    /// `C:A` becomes `A:C`. Excel writes spans in ascending order, so this only arises from a
    /// malformed file — and the alternative is a range whose `start` is past its `end`, where
    /// ``cells`` builds `3...1` and **traps**. Answering a well-formed range is a better
    /// response to bad input than bringing the process down.
    ///
    /// - Parameter reference: A range, a cell, or a whole span. An unparseable string yields
    ///   `A1` rather than trapping — this is called with whatever a file said, and an empty
    ///   string used to index an empty array.
    public init(_ reference: String) {
        let parts = reference.split(separator: ":", maxSplits: 1)
        guard let head = parts.first else {
            // `""` and `":"` both split to nothing. This used to be `parts[0]`.
            self.start = CellRef(column: 1, row: 1)
            self.end = CellRef(column: 1, row: 1)
            return
        }
        guard parts.count > 1 else {
            self.start = CellRef(String(head))
            self.end = CellRef(String(head))
            return
        }
        // Only with a colon: a bare `A` is a cell reference this initialiser has always
        // read as `A1`, and reading it as a whole column would change an answer nobody
        // asked about.
        if let span = CellRange.wholeSpan(from: head, to: parts[1]) {
            self.start = span.start
            self.end = span.end
            return
        }
        self.start = CellRef(String(head))
        self.end = CellRef(String(parts[1]))
    }

    /// A whole column or a whole row, as the range it names.
    ///
    /// `$D:$D` is every cell of column D and `$3:$3` is every cell of row 3. Excel writes
    /// both, and each half carries a letter *or* a digit but never both — which is exactly
    /// why a parser built on ``CellRef/init(_:)`` cannot read them.
    ///
    /// Exposed rather than kept private because this rule had **two implementations** and
    /// only one was right: `DefinedNameResolver` in SwiftXLSX had worked it out for defined
    /// names, which is why whole-column names round-tripped across 161,901 of them while
    /// `CellRange(_:)` was answering `A1`. One rule, one place.
    ///
    /// - Parameters:
    ///   - start: The half before the colon.
    ///   - end: The half after it.
    /// - Returns: The range, or `nil` when the pair is not a whole span.
    public static func wholeSpan(from start: Substring, to end: Substring) -> CellRange? {
        if let first = columnNumber(start), let last = columnNumber(end) {
            let ascending = first <= last
            let (low, high) = ascending ? (first, last) : (last, first)
            let (lowAbsolute, highAbsolute) = ascending
                ? (start.hasPrefix("$"), end.hasPrefix("$"))
                : (end.hasPrefix("$"), start.hasPrefix("$"))
            return CellRange(
                from: CellRef(column: low, row: 1,
                              absoluteColumn: lowAbsolute, absoluteRow: false),
                to: CellRef(column: high, row: CellRef.lastOnSheet.row,
                            absoluteColumn: highAbsolute, absoluteRow: false))
        }
        if let first = rowNumber(start), let last = rowNumber(end) {
            let ascending = first <= last
            let (low, high) = ascending ? (first, last) : (last, first)
            let (lowAbsolute, highAbsolute) = ascending
                ? (start.hasPrefix("$"), end.hasPrefix("$"))
                : (end.hasPrefix("$"), start.hasPrefix("$"))
            return CellRange(
                from: CellRef(column: 1, row: low,
                              absoluteColumn: false, absoluteRow: lowAbsolute),
                to: CellRef(column: CellRef.lastOnSheet.column, row: high,
                            absoluteColumn: false, absoluteRow: highAbsolute))
        }
        return nil
    }

    /// A fragment that is nothing but a column, as its number.
    ///
    /// - Parameter fragment: One half of a span, with or without its `$`.
    /// - Returns: The column number, or `nil` if the fragment is not all letters or names
    ///   a column past the grid's last.
    private static func columnNumber(_ fragment: Substring) -> Int? {
        let letters = fragment.hasPrefix("$") ? fragment.dropFirst() : fragment
        guard !letters.isEmpty, letters.allSatisfy(\.isLetter) else { return nil }
        var column = 0
        for character in letters {
            guard let scalar = character.uppercased().unicodeScalars.first else { return nil }
            column = column * 26 + Int(scalar.value) - 64
        }
        return (1...CellRef.lastOnSheet.column).contains(column) ? column : nil
    }

    /// A fragment that is nothing but a row, as its number.
    ///
    /// - Parameter fragment: One half of a span, with or without its `$`.
    /// - Returns: The row number, or `nil` if the fragment is not all digits or names a row
    ///   past the grid's last.
    private static func rowNumber(_ fragment: Substring) -> Int? {
        let digits = fragment.hasPrefix("$") ? fragment.dropFirst() : fragment
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber),
              let row = Int(digits) else { return nil }
        return (1...CellRef.lastOnSheet.row).contains(row) ? row : nil
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
        // A range written out by hand describes its own window and is never pulled back.
        guard extendsToLastRow || extendsToLastColumn else { return self }
        // **A whole row keeps its full width.** The reasoning above — that `$B:$B` asks for
        // whatever is in column B rather than for a million cells — holds for a column,
        // where the alternative really is 1,048,576 values. It does not hold for a row,
        // which is 16,384 at most: about a hundred kilobytes, and cheap enough to keep
        // whole.
        //
        // Clipping it costs correctness. `INDEX`, `COLUMNS`, `ROWS` and the lookups all
        // count *positions*, and a row pulled back to where the data stops has the wrong
        // ones — `INDEX('Raw'!$C$4:$XFD$4, 24)` answered `#REF!` against a fourteen-column
        // matrix where Excel reads the blank at column Z, and `COLUMNS($A$1:$XFD$1)`
        // answered `0` instead of `16384`. Measured across 46 real workbooks, that was every
        // disagreement with Excel that remained.
        //
        // A whole column and a whole sheet still pull back, because there the original
        // argument is exactly right.
        guard extendsToLastRow else { return self }
        guard let limit else { return nil }
        guard limit.row >= start.row, limit.column >= start.column else { return nil }
        let lastRow = Swift.min(end.row, limit.row)
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
