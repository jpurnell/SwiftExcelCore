import XCTest
@testable import SwiftExcelCore

/// A rectangle of cells keeps its shape.
///
/// The tests are written against the invariant rather than the implementation:
/// a matrix that cannot state its own dimensions is the defect this type exists
/// to remove, so most of these assert that the dimensions survive something.
final class CellMatrixTests: XCTestCase {

    // MARK: - Construction

    func testHoldsItsDimensions() throws {
        let matrix = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2), .number(3),
                                  .number(4), .number(5), .number(6)],
                       rows: 2, columns: 3))
        XCTAssertEqual(matrix.rows, 2)
        XCTAssertEqual(matrix.columns, 3)
        XCTAssertEqual(matrix.count, 6)
    }

    /// The invariant that makes every other guarantee possible.
    func testRejectsElementsThatDoNotFillTheRectangle() {
        XCTAssertNil(CellMatrix(elements: [.number(1), .number(2)], rows: 2, columns: 3))
        XCTAssertNil(CellMatrix(elements: [.number(1)], rows: 0, columns: 0))
    }

    func testRejectsNegativeDimensions() {
        XCTAssertNil(CellMatrix(elements: [], rows: -1, columns: 0))
        XCTAssertNil(CellMatrix(elements: [], rows: 0, columns: -1))
    }

    func testTheEmptyMatrixIsRepresentable() throws {
        let matrix = try XCTUnwrap(CellMatrix(elements: [], rows: 0, columns: 0))
        XCTAssertTrue(matrix.isEmpty)
        XCTAssertEqual(matrix.count, 0)
    }

    func testVectorInitializers() {
        let row = CellMatrix(row: [.number(1), .number(2), .number(3)])
        XCTAssertEqual(row.rows, 1)
        XCTAssertEqual(row.columns, 3)

        let column = CellMatrix(column: [.number(1), .number(2), .number(3)])
        XCTAssertEqual(column.rows, 3)
        XCTAssertEqual(column.columns, 1)
    }

    /// A row and a column of the same values are *not* equal.
    ///
    /// The whole point: these two flatten to the same list, and under the old
    /// representation nothing could tell them apart.
    func testARowIsNotAColumn() {
        XCTAssertNotEqual(CellMatrix(row: [.number(1), .number(2)]),
                          CellMatrix(column: [.number(1), .number(2)]))
    }

    // MARK: - Access

    func testRowMajorIndexing() throws {
        // 1 2 3
        // 4 5 6
        let matrix = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2), .number(3),
                                  .number(4), .number(5), .number(6)],
                       rows: 2, columns: 3))
        XCTAssertEqual(matrix[0, 0], .number(1))
        XCTAssertEqual(matrix[0, 2], .number(3))
        XCTAssertEqual(matrix[1, 0], .number(4))
        XCTAssertEqual(matrix[1, 2], .number(6))
    }

    func testBoundsCheckedAccess() throws {
        let matrix = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2)], rows: 1, columns: 2))
        XCTAssertEqual(matrix.element(row: 0, column: 1), .number(2))
        XCTAssertNil(matrix.element(row: 1, column: 0))
        XCTAssertNil(matrix.element(row: 0, column: 2))
        XCTAssertNil(matrix.element(row: -1, column: 0))
        XCTAssertNil(matrix.element(row: 0, column: -1))
    }

    func testRowAndColumnSlices() throws {
        let matrix = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2), .number(3),
                                  .number(4), .number(5), .number(6)],
                       rows: 2, columns: 3))
        XCTAssertEqual(matrix.row(1), [.number(4), .number(5), .number(6)])
        XCTAssertEqual(matrix.column(2), [.number(3), .number(6)])
        XCTAssertNil(matrix.row(2))
        XCTAssertNil(matrix.column(3))
    }

    // MARK: - Vectors

    func testIsVector() throws {
        XCTAssertTrue(CellMatrix(row: [.number(1), .number(2)]).isVector)
        XCTAssertTrue(CellMatrix(column: [.number(1), .number(2)]).isVector)
        XCTAssertTrue(CellMatrix(row: [.number(1)]).isVector)

        let block = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2), .number(3), .number(4)],
                       rows: 2, columns: 2))
        XCTAssertFalse(block.isVector)
    }

    // MARK: - Transposition

    func testTransposeAVector() {
        let column = CellMatrix(column: [.number(1), .number(2), .number(3)])
        let transposed = column.transposed()
        XCTAssertEqual(transposed.rows, 1)
        XCTAssertEqual(transposed.columns, 3)
        XCTAssertEqual(transposed.elements, [.number(1), .number(2), .number(3)])
    }

    func testTransposeABlockMovesElements() throws {
        // 1 2 3        1 4
        // 4 5 6   ->   2 5
        //              3 6
        let matrix = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2), .number(3),
                                  .number(4), .number(5), .number(6)],
                       rows: 2, columns: 3))
        let transposed = matrix.transposed()
        XCTAssertEqual(transposed.rows, 3)
        XCTAssertEqual(transposed.columns, 2)
        XCTAssertEqual(transposed.elements,
                       [.number(1), .number(4),
                        .number(2), .number(5),
                        .number(3), .number(6)])
    }

    func testTransposeTwiceIsTheIdentity() throws {
        let matrix = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .text("b"), .blank,
                                  .bool(true), .error(.na), .number(6)],
                       rows: 2, columns: 3))
        XCTAssertEqual(matrix.transposed().transposed(), matrix)
    }

    func testTransposeTheEmptyMatrix() throws {
        let empty = try XCTUnwrap(CellMatrix(elements: [], rows: 0, columns: 0))
        XCTAssertEqual(empty.transposed(), empty)
    }

    // MARK: - Blanks

    /// Blanks occupy positions rather than being absent.
    ///
    /// This is the property the old flat representation could not hold, and the
    /// reason `INDEX` walked off the end of its own range.
    func testBlanksHoldTheirPlace() throws {
        let matrix = try XCTUnwrap(
            CellMatrix(elements: [.number(10), .blank, .number(30), .number(40)],
                       rows: 4, columns: 1))
        XCTAssertEqual(matrix.count, 4)
        XCTAssertEqual(matrix[2, 0], .number(30))
    }

    // MARK: - Value semantics

    func testEquatableAndHashable() throws {
        let a = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2)], rows: 1, columns: 2))
        let b = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2)], rows: 1, columns: 2))
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    /// A matrix is a `CellValue`, and nesting still works.
    func testNestsInsideACellValue() throws {
        let inner = CellMatrix(row: [.number(1), .number(2)])
        let outer = CellMatrix(row: [.array(inner), .number(3)])
        XCTAssertEqual(outer.columns, 2)
        guard case .array(let recovered) = outer[0, 0] else {
            return XCTFail("expected a nested matrix")
        }
        XCTAssertEqual(recovered, inner)
    }

    // MARK: - Spilling

    // One formula fills a rectangle. When the result's shape and the span's shape
    // disagree, Excel broadcasts a vector, pads what it cannot fill with #N/A, and
    // truncates what does not fit.

    func testAnExactFitIsUnchanged() throws {
        let matrix = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2), .number(3),
                                  .number(4), .number(5), .number(6)],
                       rows: 2, columns: 3))
        XCTAssertEqual(matrix.spilled(toRows: 2, columns: 3), matrix)
    }

    /// A single value fills the whole span — the commonest case, and the reason a
    /// scalar entered as an array formula shows up everywhere at once.
    func testASingleValueFillsTheSpan() {
        let filled = CellMatrix(single: .number(7)).spilled(toRows: 2, columns: 3)
        XCTAssertEqual(filled.rows, 2)
        XCTAssertEqual(filled.columns, 3)
        XCTAssertEqual(filled.elements, Array(repeating: .number(7), count: 6))
    }

    /// A row repeats downwards.
    func testARowBroadcastsDown() throws {
        let row = CellMatrix(row: [.number(1), .number(2)])
        let filled = row.spilled(toRows: 3, columns: 2)
        XCTAssertEqual(filled.rows, 3)
        XCTAssertEqual(filled.columns, 2)
        XCTAssertEqual(filled.elements, [.number(1), .number(2),
                                         .number(1), .number(2),
                                         .number(1), .number(2)])
    }

    /// A column repeats across.
    func testAColumnBroadcastsAcross() {
        let column = CellMatrix(column: [.number(1), .number(2)])
        let filled = column.spilled(toRows: 2, columns: 3)
        XCTAssertEqual(filled.elements, [.number(1), .number(1), .number(1),
                                         .number(2), .number(2), .number(2)])
    }

    /// What cannot be filled is `#N/A`, which is what Excel shows.
    func testAShortResultPadsWithNotAvailable() throws {
        let block = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2), .number(3), .number(4)],
                       rows: 2, columns: 2))
        let filled = block.spilled(toRows: 3, columns: 3)
        XCTAssertEqual(filled[0, 0], .number(1))
        XCTAssertEqual(filled[0, 2], .error(.na), "no third column to take from")
        XCTAssertEqual(filled[2, 0], .error(.na), "no third row to take from")
    }

    /// What does not fit is dropped.
    func testALongResultIsTruncated() throws {
        let block = try XCTUnwrap(
            CellMatrix(elements: [.number(1), .number(2), .number(3),
                                  .number(4), .number(5), .number(6)],
                       rows: 2, columns: 3))
        let filled = block.spilled(toRows: 1, columns: 2)
        XCTAssertEqual(filled.rows, 1)
        XCTAssertEqual(filled.columns, 2)
        XCTAssertEqual(filled.elements, [.number(1), .number(2)])
    }

    /// A vector only broadcasts along the dimension that is 1. A 1×2 row into a
    /// 3×3 span repeats down but has no third column to offer.
    func testBroadcastAndPadTogether() {
        let filled = CellMatrix(row: [.number(1), .number(2)]).spilled(toRows: 2, columns: 3)
        XCTAssertEqual(filled.elements, [.number(1), .number(2), .error(.na),
                                         .number(1), .number(2), .error(.na)])
    }

    func testSpillingNothingIsAllNotAvailable() throws {
        let empty = try XCTUnwrap(CellMatrix(elements: [], rows: 0, columns: 0))
        let filled = empty.spilled(toRows: 2, columns: 2)
        XCTAssertEqual(filled.elements, Array(repeating: .error(.na), count: 4))
    }

    func testSpillingToNothingIsEmpty() {
        XCTAssertTrue(CellMatrix(single: .number(1)).spilled(toRows: 0, columns: 0).isEmpty)
    }

    /// Blanks spill as blanks, not as `#N/A` — an empty cell inside a result is a
    /// value the result has, and only cells the result cannot reach are `#N/A`.
    func testBlanksSpillAsBlanks() {
        let filled = CellMatrix(row: [.number(1), .blank]).spilled(toRows: 1, columns: 3)
        XCTAssertEqual(filled.elements, [.number(1), .blank, .error(.na)])
    }
}
