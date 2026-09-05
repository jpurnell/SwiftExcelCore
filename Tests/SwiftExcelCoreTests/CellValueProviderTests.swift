import XCTest
@testable import SwiftExcelCore

/// Reading a range keeps its shape and its holes.
final class CellValueProviderTests: XCTestCase {

    /// A provider that implements only the two single-cell requirements, so the
    /// protocol's own default is what these tests exercise.
    private struct SparseCells: CellValueProvider {
        let stored: [CellRef: CellValue]
        let sheets: Set<String>

        init(_ stored: [CellRef: CellValue], sheets: Set<String> = ["Sheet1"]) {
            self.stored = stored
            self.sheets = sheets
        }

        func value(at ref: CellRef) -> CellValue? { stored[ref] }

        func lastPopulatedCell() -> CellRef? {
            guard let maxColumn = stored.keys.map(\.column).max(),
                  let maxRow = stored.keys.map(\.row).max() else { return nil }
            return CellRef(column: maxColumn, row: maxRow)
        }

        func lastPopulatedCell(inSheet: String) -> CellRef? {
            sheets.contains(inSheet) ? lastPopulatedCell() : nil
        }

        func value(at ref: CellRef, inSheet: String) -> CellValue? {
            sheets.contains(inSheet) ? stored[ref] : nil
        }

        func values(in range: CellRange) -> [CellValue] {
            range.cells.compactMap { stored[$0] }
        }

        func values(in range: CellRange, inSheet: String) -> [CellValue] {
            values(in: range)
        }
    }

    private func range(_ from: String, _ to: String) -> CellRange {
        CellRange(from: CellRef(from), to: CellRef(to))
    }

    // MARK: - Shape

    func testAReadKeepsTheRangeDimensions() throws {
        let cells = SparseCells([
            CellRef("A1"): .number(1), CellRef("B1"): .number(2), CellRef("C1"): .number(3),
            CellRef("A2"): .number(4), CellRef("B2"): .number(5), CellRef("C2"): .number(6),
        ])
        let matrix = try XCTUnwrap(cells.matrix(in: range("A1", "C2")))
        XCTAssertEqual(matrix.rows, 2)
        XCTAssertEqual(matrix.columns, 3)
        XCTAssertEqual(matrix[1, 0], .number(4))
    }

    func testASingleCellIsAOneByOne() throws {
        let cells = SparseCells([CellRef("A1"): .number(7)])
        let matrix = try XCTUnwrap(cells.matrix(in: range("A1", "A1")))
        XCTAssertEqual(matrix.rows, 1)
        XCTAssertEqual(matrix.columns, 1)
        XCTAssertEqual(matrix[0, 0], .number(7))
    }

    func testAColumnKeepsItsOrientation() throws {
        let cells = SparseCells([
            CellRef("A1"): .number(1), CellRef("A2"): .number(2), CellRef("A3"): .number(3),
        ])
        let matrix = try XCTUnwrap(cells.matrix(in: range("A1", "A3")))
        XCTAssertEqual(matrix.rows, 3)
        XCTAssertEqual(matrix.columns, 1)
        XCTAssertFalse(matrix.isVector == false)
    }

    // MARK: - Blanks

    /// The defect this whole change exists to remove.
    ///
    /// `A1:A4` with `A2` empty is four cells, not three. Under the old read the
    /// blank vanished and every later position shifted up one.
    func testEmptyCellsBecomeBlanksInPlace() throws {
        let cells = SparseCells([
            CellRef("A1"): .number(10),
            CellRef("A3"): .number(30),
            CellRef("A4"): .number(40),
        ])
        let matrix = try XCTUnwrap(cells.matrix(in: range("A1", "A4")))
        XCTAssertEqual(matrix.count, 4)
        XCTAssertEqual(matrix.elements, [.number(10), .blank, .number(30), .number(40)])
    }

    func testAnEntirelyEmptyRangeIsStillARectangle() throws {
        let matrix = try XCTUnwrap(SparseCells([:]).matrix(in: range("A1", "B3")))
        XCTAssertEqual(matrix.rows, 3)
        XCTAssertEqual(matrix.columns, 2)
        XCTAssertEqual(matrix.elements, Array(repeating: .blank, count: 6))
    }

    // MARK: - Sheets

    func testReadingFromANamedSheet() throws {
        let cells = SparseCells([CellRef("A1"): .number(1), CellRef("A2"): .number(2)])
        let matrix = try XCTUnwrap(cells.matrix(in: range("A1", "A2"), inSheet: "Sheet1"))
        XCTAssertEqual(matrix.elements, [.number(1), .number(2)])
    }

    /// A sheet that is not there reads as blanks, matching what `values(in:_:)`
    /// documented: an absent sheet is empty, not an error.
    func testAMissingSheetReadsAsBlanks() throws {
        let cells = SparseCells([CellRef("A1"): .number(1)])
        let matrix = try XCTUnwrap(cells.matrix(in: range("A1", "A2"), inSheet: "Nope"))
        XCTAssertEqual(matrix.elements, [.blank, .blank])
    }

    // MARK: - Whole-column ranges

    // `$B:$B` is not a request for 1,048,576 cells. It is a request for whatever is
    // in that column, which is what `DependencyGraph` already says about the same
    // notation. Reading it stops at the last cell the sheet actually holds.

    func testAWholeColumnStopsAtTheLastPopulatedCell() throws {
        let cells = SparseCells([
            CellRef("A1"): .number(1),
            CellRef("A2"): .number(2),
            CellRef("A3"): .number(3),
        ])
        let wholeColumn = CellRange(from: CellRef(column: 1, row: 1),
                                    to: CellRef(column: 1, row: 1_048_576))
        let matrix = cells.matrix(in: wholeColumn)
        XCTAssertEqual(matrix.count, 3, "not 1,048,576")
        XCTAssertEqual(matrix.rows, 3)
        XCTAssertEqual(matrix.columns, 1)
    }

    /// Clipping moves the far corner only. Positions are counted from the range's
    /// own origin, so `INDEX($A:$A, 3)` must still mean the third row.
    func testClippingKeepsTheOrigin() throws {
        let cells = SparseCells([
            CellRef("A3"): .number(30),
            CellRef("A4"): .number(40),
        ])
        let wholeColumn = CellRange(from: CellRef(column: 1, row: 1),
                                    to: CellRef(column: 1, row: 1_048_576))
        let matrix = cells.matrix(in: wholeColumn)
        XCTAssertEqual(matrix.elements, [.blank, .blank, .number(30), .number(40)],
                       "rows 1 and 2 are blank and still occupy their places")
    }

    func testAWholeRowStopsAtTheLastPopulatedColumn() throws {
        let cells = SparseCells([CellRef("A1"): .number(1), CellRef("C1"): .number(3)])
        let wholeRow = CellRange(from: CellRef(column: 1, row: 1),
                                 to: CellRef(column: 16_384, row: 1))
        let matrix = cells.matrix(in: wholeRow)
        XCTAssertEqual(matrix.count, 3)
        XCTAssertEqual(matrix.rows, 1)
        XCTAssertEqual(matrix.columns, 3)
    }

    /// A range entirely inside the populated area is untouched, blanks and all.
    func testASmallRangeIsNotClipped() throws {
        let cells = SparseCells([CellRef("A1"): .number(1), CellRef("D4"): .number(4)])
        let matrix = cells.matrix(in: range("A1", "B2"))
        XCTAssertEqual(matrix.rows, 2)
        XCTAssertEqual(matrix.columns, 2)
        XCTAssertEqual(matrix.elements, [.number(1), .blank, .blank, .blank])
    }

    /// A provider holding nothing clips to nothing rather than to the whole grid.
    func testAnEmptySheetYieldsAnEmptyRectangle() throws {
        let wholeColumn = CellRange(from: CellRef(column: 1, row: 1),
                                    to: CellRef(column: 1, row: 1_048_576))
        XCTAssertTrue(SparseCells([:]).matrix(in: wholeColumn).isEmpty)
    }

    /// A provider that does not know its bounds names the grid's last cell, and
    /// gets exactly the range it asked for.
    func testARangeIsTakenLiterallyWhenBoundsAreUnknown() throws {
        struct Unbounded: CellValueProvider {
            func value(at ref: CellRef) -> CellValue? { nil }
            func value(at ref: CellRef, inSheet: String) -> CellValue? { nil }
            func lastPopulatedCell() -> CellRef? { .lastOnSheet }
            func lastPopulatedCell(inSheet: String) -> CellRef? { .lastOnSheet }
            func values(in range: CellRange) -> [CellValue] { [] }
            func values(in range: CellRange, inSheet: String) -> [CellValue] { [] }
        }
        let matrix = Unbounded().matrix(in: CellRange(from: CellRef("A1"), to: CellRef("C2")))
        XCTAssertEqual(matrix.rows, 2)
        XCTAssertEqual(matrix.columns, 3)
    }

    // MARK: - The deprecated flat read

    /// `values(in:)` keeps its documented behaviour exactly: blanks skipped.
    func testTheFlatReadStillSkipsBlanks() {
        let cells = SparseCells([CellRef("A1"): .number(10), CellRef("A3"): .number(30)])
        XCTAssertEqual(cells.values(in: range("A1", "A4")), [.number(10), .number(30)])
    }
}
