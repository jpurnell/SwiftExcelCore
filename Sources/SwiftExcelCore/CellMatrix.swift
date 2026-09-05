/// A rectangle of cell values, carrying its own dimensions.
///
/// A range of cells is a rectangle, and a rectangle that cannot state its width
/// is not one. This type exists because the flat `[CellValue]` it replaces could
/// not: consumers had to re-derive the shape, and two of them derived it wrongly.
/// `INDEX` counted positions in a list its blanks had been removed from, and
/// `VLOOKUP` guessed its table's width by testing which divisors came out even.
///
/// ## Row-major order
///
/// ``elements`` runs left to right, then top to bottom — the same order
/// ``CellRange/cells`` produces, so a range and its values agree by construction.
/// The element at a position is at index `row * columns + column`.
///
/// ```swift
/// // 1 2 3
/// // 4 5 6
/// let matrix = CellMatrix(
///     elements: [.number(1), .number(2), .number(3),
///                .number(4), .number(5), .number(6)],
///     rows: 2, columns: 3)
/// matrix?[1, 0]   // .number(4)
/// ```
///
/// ## Blanks are present, not absent
///
/// An empty cell inside a rectangle is ``CellValue/blank`` at its own position,
/// never a gap that closes up. This is the property that makes positional access
/// meaningful: `INDEX(A1:A4, 3)` must reach the third cell whether or not the
/// second one holds anything.
///
/// ## Shape is an invariant
///
/// ``init(elements:rows:columns:)`` fails unless the count fills the rectangle
/// exactly, so a matrix whose dimensions disagree with its contents cannot be
/// built. Every accessor is free to trust `rows` and `columns` afterwards.
public struct CellMatrix: Equatable, Hashable, Sendable {

    /// The values, in row-major order: index `row * columns + column`.
    public let elements: [CellValue]

    /// The number of rows.
    public let rows: Int

    /// The number of columns.
    public let columns: Int

    /// Creates a matrix, or fails if the elements do not fill the rectangle.
    ///
    /// Failable rather than trapping, because the count usually comes from a
    /// caller's own arithmetic, and a wrong rectangle is a recoverable mistake —
    /// Excel's answer to one is `#VALUE!`, not a crash.
    ///
    /// - Parameters:
    ///   - elements: The values, row-major. Must number exactly `rows * columns`.
    ///   - rows: The row count. Must not be negative.
    ///   - columns: The column count. Must not be negative.
    public init?(elements: [CellValue], rows: Int, columns: Int) {
        guard rows >= 0, columns >= 0, elements.count == rows * columns else { return nil }
        self.elements = elements
        self.rows = rows
        self.columns = columns
    }

    /// Creates a single row.
    ///
    /// - Parameter elements: The values, left to right.
    public init(row elements: [CellValue]) {
        self.elements = elements
        self.rows = elements.isEmpty ? 0 : 1
        self.columns = elements.count
    }

    /// Creates a single column.
    ///
    /// - Parameter elements: The values, top to bottom.
    public init(column elements: [CellValue]) {
        self.elements = elements
        self.rows = elements.count
        self.columns = elements.isEmpty ? 0 : 1
    }

    /// Creates a matrix holding one value.
    ///
    /// - Parameter value: The value.
    public init(single value: CellValue) {
        self.elements = [value]
        self.rows = 1
        self.columns = 1
    }

    // MARK: - Measuring

    /// The total number of cells.
    public var count: Int { elements.count }

    /// Whether the rectangle holds nothing.
    public var isEmpty: Bool { elements.isEmpty }

    /// Whether either dimension is 1.
    ///
    /// The distinction `TRANSPOSE` and the lookup functions turn on: a vector has
    /// an unambiguous reading order, a block does not.
    public var isVector: Bool { rows == 1 || columns == 1 }

    // MARK: - Access

    /// The value at a position.
    ///
    /// Traps when out of bounds, matching the standard library's convention for
    /// subscripts. Use ``element(row:column:)`` where the position comes from
    /// outside and might not be valid — which, for a spreadsheet formula, is
    /// almost always.
    ///
    /// - Parameters:
    ///   - row: The row, counted from zero.
    ///   - column: The column, counted from zero.
    public subscript(row: Int, column: Int) -> CellValue {
        precondition(row >= 0 && row < rows, "row \(row) out of bounds (\(rows) rows)")
        precondition(column >= 0 && column < columns,
                     "column \(column) out of bounds (\(columns) columns)")
        return elements[row * columns + column]
    }

    /// The value at a position, or `nil` if there is no such position.
    ///
    /// - Parameters:
    ///   - row: The row, counted from zero.
    ///   - column: The column, counted from zero.
    /// - Returns: The value, or `nil` when out of bounds.
    public func element(row: Int, column: Int) -> CellValue? {
        guard row >= 0, row < rows, column >= 0, column < columns else { return nil }
        return elements[row * columns + column]
    }

    /// One row's values, left to right.
    ///
    /// - Parameter index: The row, counted from zero.
    /// - Returns: The values, or `nil` when there is no such row.
    public func row(_ index: Int) -> [CellValue]? {
        guard index >= 0, index < rows else { return nil }
        let start = index * columns
        return Array(elements[start..<(start + columns)])
    }

    /// One column's values, top to bottom.
    ///
    /// - Parameter index: The column, counted from zero.
    /// - Returns: The values, or `nil` when there is no such column.
    public func column(_ index: Int) -> [CellValue]? {
        guard index >= 0, index < columns else { return nil }
        return (0..<rows).map { elements[$0 * columns + index] }
    }

    // MARK: - Transforming

    /// The rectangle this result becomes when one formula fills a span.
    ///
    /// A formula entered over a range evaluates once and its result fills the
    /// whole rectangle. The result's shape and the span's shape need not agree, and
    /// Excel reconciles them in three ways, all of them here:
    ///
    /// - **Broadcast.** A dimension of 1 repeats. A single row fills every row of
    ///   the span, a single column every column, and a lone value fills all of it —
    ///   which is why a scalar entered as an array formula appears everywhere at
    ///   once.
    /// - **Pad.** A cell the result cannot reach is `#N/A`. Not blank: blank is a
    ///   value the result could have held, and this is the absence of one.
    /// - **Truncate.** A result larger than the span loses what does not fit.
    ///
    /// A blank *inside* the result stays blank. Only cells beyond the result's
    /// reach become `#N/A`, which is the distinction that makes a spilled rectangle
    /// readable: `#N/A` means "the formula had nothing for this cell."
    ///
    /// ```swift
    /// let row = CellMatrix(row: [.number(1), .number(2)])
    /// row.spilled(toRows: 2, columns: 3).elements
    /// // [1, 2, #N/A,
    /// //  1, 2, #N/A]
    /// ```
    ///
    /// - Parameters:
    ///   - rows: The span's row count. Negative counts as zero.
    ///   - columns: The span's column count. Negative counts as zero.
    /// - Returns: A rectangle of exactly the requested shape.
    public func spilled(toRows rows: Int, columns: Int) -> CellMatrix {
        let height = Swift.max(rows, 0)
        let width = Swift.max(columns, 0)
        guard height > 0, width > 0 else { return CellMatrix(row: []) }

        var result: [CellValue] = []
        result.reserveCapacity(height * width)
        for row in 0..<height {
            // A single row repeats down; a single column repeats across. Anything
            // else keeps its own index and runs out.
            let sourceRow = self.rows == 1 ? 0 : row
            for column in 0..<width {
                let sourceColumn = self.columns == 1 ? 0 : column
                result.append(element(row: sourceRow, column: sourceColumn) ?? .error(.na))
            }
        }
        return CellMatrix(elements: result, rows: height, columns: width)
            ?? CellMatrix(row: [])
    }

    /// The matrix with rows and columns exchanged.
    ///
    /// What `TRANSPOSE` computes. Iterative rather than recursive, and total: every
    /// rectangle has a transpose, including the empty one.
    ///
    /// - Returns: A matrix of `columns` rows and `rows` columns.
    public func transposed() -> CellMatrix {
        guard !isEmpty else { return self }
        var result: [CellValue] = []
        result.reserveCapacity(elements.count)
        for column in 0..<columns {
            for row in 0..<rows {
                result.append(elements[row * columns + column])
            }
        }
        // The rectangle is the same size with its sides swapped, so this cannot
        // fail; the fallback keeps the promise without a force unwrap.
        return CellMatrix(elements: result, rows: columns, columns: rows)
            ?? CellMatrix(row: [])
    }
}
