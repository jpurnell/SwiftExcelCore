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

    // MARK: - Refusal

    /// A whole column is 1,048,576 cells and must not be materialized.
    ///
    /// `DependencyGraph` learned this once already. Refusing is representable —
    /// that is what the optional return is for.
    func testAnOversizedRangeIsRefused() {
        let wholeColumn = CellRange(from: CellRef(column: 2, row: 1),
                                    to: CellRef(column: 2, row: 1_048_576))
        XCTAssertNil(SparseCells([:]).matrix(in: wholeColumn))
    }

    func testARangeAtTheLimitIsAllowed() throws {
        let rows = CellMatrix.maximumCells
        let atLimit = CellRange(from: CellRef(column: 1, row: 1),
                                to: CellRef(column: 1, row: rows))
        let matrix = try XCTUnwrap(SparseCells([:]).matrix(in: atLimit))
        XCTAssertEqual(matrix.count, rows)
    }

    func testOneCellPastTheLimitIsRefused() {
        let past = CellRange(from: CellRef(column: 1, row: 1),
                             to: CellRef(column: 1, row: CellMatrix.maximumCells + 1))
        XCTAssertNil(SparseCells([:]).matrix(in: past))
    }

    // MARK: - The deprecated flat read

    /// `values(in:)` keeps its documented behaviour exactly: blanks skipped.
    func testTheFlatReadStillSkipsBlanks() {
        let cells = SparseCells([CellRef("A1"): .number(10), CellRef("A3"): .number(30)])
        XCTAssertEqual(cells.values(in: range("A1", "A4")), [.number(10), .number(30)])
    }
}
