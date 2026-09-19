import XCTest
@testable import SwiftExcelCore

/// `CellRange(_: String)` and the whole-span shorthands.
///
/// ## What this was doing
///
/// The initialiser split on the colon and handed each half to `CellRef(_:)`, which defaults a
/// missing row to 1 and a missing column to 0. So:
///
/// | written | was | every cell in it |
/// |---|---|---|
/// | `A:A` | `A1` | one cell, where a column was meant |
/// | `A:C` | `A1:C1` | a plausible 1×3 |
/// | `1:1` | column **0**, row 1 | no cell: columns are 1-based |
/// | `2:5` | column **0**, rows 2–5 | four cells that cannot exist |
///
/// The column cases were merely wrong. The row cases produced references **outside the
/// grid** — `rowCount` reported 4 for `2:5`, so the range looked well-formed while every
/// `CellRef` it enumerated had column 0.
///
/// ## Where it mattered
///
/// `WorksheetParser` builds ranges this way from four attributes read out of real files —
/// an array formula's `ref`, `autoFilter`, `mergeCell`, and a data validation's `sqref`.
/// A data validation over a whole column is ordinary.
///
/// Defined names were **not** affected: `DefinedNameResolver` has its own `wholeSpan`, which
/// does this correctly. That is the second implementation of one rule, and the reason this
/// one was never noticed — the path that mattered most had quietly been fixed already.
final class CellRangeStringParsingTests: XCTestCase {

    private static let lastRow = CellRef.lastOnSheet.row
    private static let lastColumn = CellRef.lastOnSheet.column

    // MARK: - Whole columns

    func testAWholeColumnSpansEveryRow() {
        let range = CellRange("A:A")
        XCTAssertEqual(range.start, CellRef(column: 1, row: 1))
        XCTAssertEqual(range.end.column, 1)
        XCTAssertEqual(range.end.row, Self.lastRow)
        XCTAssertEqual(range.rowCount, Self.lastRow)
        XCTAssertEqual(range.columnCount, 1)
    }

    func testASpanOfColumns() {
        let range = CellRange("A:C")
        XCTAssertEqual(range.columnCount, 3)
        XCTAssertEqual(range.rowCount, Self.lastRow)
    }

    /// The `$` is carried, so a writer can put back what it read.
    func testTheAbsoluteMarkersSurvive() {
        let range = CellRange("$D:$D")
        XCTAssertTrue(range.start.absoluteColumn)
        XCTAssertTrue(range.end.absoluteColumn)
        // The row was never written, so it is not absolute — the same choice
        // `DefinedNameResolver.wholeSpan` makes for the same notation.
        XCTAssertFalse(range.start.absoluteRow)
        XCTAssertEqual(range.columnCount, 1)
        XCTAssertEqual(range.rowCount, Self.lastRow)
    }

    // MARK: - Whole rows

    /// **The case that produced column zero.**
    func testAWholeRowSpansEveryColumn() {
        let range = CellRange("1:1")
        XCTAssertEqual(range.start.column, 1, "columns are 1-based; zero is not a column")
        XCTAssertEqual(range.start.row, 1)
        XCTAssertEqual(range.end.column, Self.lastColumn)
        XCTAssertEqual(range.end.row, 1)
        XCTAssertEqual(range.rowCount, 1)
        XCTAssertEqual(range.columnCount, Self.lastColumn)
    }

    func testASpanOfRows() {
        let range = CellRange("2:5")
        XCTAssertEqual(range.start.column, 1)
        XCTAssertEqual(range.rowCount, 4)
        XCTAssertEqual(range.columnCount, Self.lastColumn)
    }

    func testTheAbsoluteRowMarkerSurvives() {
        let range = CellRange("$3:$3")
        XCTAssertTrue(range.start.absoluteRow)
        XCTAssertTrue(range.end.absoluteRow)
        XCTAssertFalse(range.start.absoluteColumn)
        XCTAssertEqual(range.rowCount, 1)
    }

    /// Every cell a whole span enumerates is a real cell.
    ///
    /// The property the old behaviour broke, and the one worth stating: a range that reports
    /// four rows and then hands out four references to column zero is worse than one that
    /// refuses, because the count looks right.
    func testEveryEnumeratedCellIsOnTheGrid() {
        for reference in ["2:5", "1:1"] {
            let range = CellRange(reference)
            // Only the first row's worth — 16,384 references is enough to make the point
            // without building 65,536 of them.
            let sample = CellRange(from: range.start,
                                   to: CellRef(column: Swift.min(range.end.column, 8),
                                               row: range.end.row)).cells
            XCTAssertFalse(sample.isEmpty, reference)
            for cell in sample {
                XCTAssertGreaterThanOrEqual(cell.column, 1, "\(reference) gave column 0")
                XCTAssertGreaterThanOrEqual(cell.row, 1, "\(reference) gave row 0")
            }
        }
    }

    // MARK: - Unchanged

    func testOrdinaryRangesAreUnaffected() {
        let range = CellRange("A1:B10")
        XCTAssertEqual(range.reference, "A1:B10")
        XCTAssertEqual(range.rowCount, 10)
        XCTAssertEqual(range.columnCount, 2)
    }

    func testASingleCellIsUnaffected() {
        XCTAssertEqual(CellRange("A1").reference, "A1")
        XCTAssertEqual(CellRange("$B$7").reference, "$B$7")
    }

    func testMixedAbsoluteRangesAreUnaffected() {
        XCTAssertEqual(CellRange("$A$1:$B$10").reference, "$A$1:$B$10")
    }

    // MARK: - Degenerate input

    /// An empty string used to **trap**: `split` returns nothing and `parts[0]` indexes it.
    ///
    /// A non-failable initialiser cannot refuse, so it answers `A1` — and the point is that
    /// it answers at all. A reader handed a malformed attribute should not bring the process
    /// down; `WorksheetParser` calls this with whatever the file said.
    func testAnEmptyStringDoesNotTrap() {
        XCTAssertEqual(CellRange("").reference, "A1")
        XCTAssertEqual(CellRange(":").reference, "A1")
    }
}
