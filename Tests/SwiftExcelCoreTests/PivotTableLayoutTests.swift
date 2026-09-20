import XCTest
@testable import SwiftExcelCore

/// Where a pivot table sits, and how its grand total is found.
///
/// **The values come from a real workbook.** `Amazon Reporting thru 05-15-18.xlsx` renders a
/// pivot at `M1:O253` whose second data field is `"Sum of # Minutes Streamed"`, and Excel's
/// cached answer for `GETPIVOTDATA("Sum of # Minutes Streamed", 'W-E Nov 18'!$M$1)` is the
/// value sitting at `O253` — byte-identical. That is the whole mechanism: no aggregation, no
/// pivot cache, a lookup into a table already rendered onto the sheet.
final class PivotTableLayoutTests: XCTestCase {

    /// The corpus pivot, as the file declares it.
    private let streams = PivotTableLayout(
        sheet: "W-E Nov 18",
        range: CellRange(from: CellRef("M1"), to: CellRef("O253")),
        firstDataRow: 1, firstDataCol: 1,
        dataFields: ["Sum of # Streams", "Sum of # Minutes Streamed"],
        hasRowGrandTotals: true, hasColumnGrandTotals: true)

    // MARK: - Which table a cell belongs to

    func testTheAnchorAndAnyOtherCellAreBothInside() {
        XCTAssertTrue(streams.contains(CellRef("M1")), "the anchor, which is what formulas use")
        XCTAssertTrue(streams.contains(CellRef("O253")), "the far corner")
        XCTAssertTrue(streams.contains(CellRef("N100")), "and anything between")
    }

    func testCellsOutsideTheRangeAreNotInside() {
        XCTAssertFalse(streams.contains(CellRef("L1")), "one column left")
        XCTAssertFalse(streams.contains(CellRef("P1")), "one column right")
        XCTAssertFalse(streams.contains(CellRef("M254")), "one row below")
    }

    // MARK: - Finding the pieces

    func testTheHeaderRowIsWhereTheFieldNamesAre() {
        // `M1` `N1` `O1` hold "Row Labels", "Sum of # Streams", "Sum of # Minutes Streamed".
        XCTAssertEqual(streams.headerRow, 1)
    }

    /// The grand total is the last row of the range, not a row labelled `"Grand Total"`.
    ///
    /// **Measured, and the label would have been wrong.** A pivot in
    /// `Dot Com YTD Performance Report 6 20.xlsx` with `rowGrandTotals="0"` ends on a row
    /// reading `"KEY Total"` — a *subtotal*. A match for `"…Total"` would have taken it for a
    /// grand total and returned the wrong number without complaining.
    func testTheGrandTotalIsTheLastRowWhenThereIsOne() {
        XCTAssertEqual(streams.grandTotalRow, 253)
    }

    func testThereIsNoGrandTotalRowWhenTheTableRendersNone() {
        let noTotals = PivotTableLayout(
            sheet: "Data",
            range: CellRange(from: CellRef("AD130"), to: CellRef("AL176")),
            firstDataRow: 1, firstDataCol: 1,
            dataFields: ["Sum of Visits"],
            hasRowGrandTotals: false, hasColumnGrandTotals: false)
        XCTAssertNil(noTotals.grandTotalRow,
                     "rowGrandTotals=0, so the last row is ordinary and must not be read as a total")
    }
}
