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

// MARK: - The axes, for field/item pairs

/// Where each axis of a pivot sits, measured from `Dot Com YTD Performance Report 6 20.xlsx`.
///
/// **The fixture is `pivotTable8.xml`, rendered at `C134:L243` on `NED Mix`.** It is the shape
/// 3,574 corpus cells ask about, and every number below was read out of the file rather than
/// reasoned about:
///
/// ```
/// 131  SalesChannelRollUp | (All)                                    ← page fields, ABOVE the range
/// 132  ActivityDetail     | Connect
/// 134  Sum of Subs        |        |             |        | FME_Calc ← captions       (start + 0)
/// 135  Scenario | Region  | LOBMix_noXH | BP/IP  | 2014-01-21 | …    ← names + items  (start + 1)
/// 136  CY       | GBR     | V           |        | 303        | …    ← data           (start + 2)
/// 142           |         | VD Total    |        | 2076       | …    ← a subtotal
/// 243  Grand Total                               | 48095      | …    ← the grand total
/// ```
final class PivotTableAxisTests: XCTestCase {

    /// `<location ref="C134:L243" firstHeaderRow="1" firstDataRow="2" firstDataCol="4"
    ///  rowPageCount="2"/>`, `rowFields` `4 0 7 16`, `colFields` `1`, `pageFields` `9 6`.
    private let mix = PivotTableLayout(
        sheet: "NED Mix",
        range: CellRange(from: CellRef("C134"), to: CellRef("L243")),
        firstHeaderRow: 1, firstDataRow: 2, firstDataCol: 4,
        dataFields: ["Sum of Subs"], dataFieldSources: ["Subs"],
        rowFields: [.field("Scenario"), .field("Region"),
                    .field("LOBMix_noXH"), .field("BP/IP")],
        columnFields: [.field("FME_Calc")],
        pageFields: ["SalesChannelRollUp", "ActivityDetail"],
        pageFieldRowCount: 2,
        hasRowGrandTotals: true, hasColumnGrandTotals: true)

    // MARK: Rows

    /// `firstHeaderRow` is its own attribute and is **not** `firstDataRow - 1`.
    ///
    /// They coincide here, and they coincide on the Amazon fixture, which is exactly the
    /// condition under which deriving one from the other survives until it doesn't.
    func testTheHeaderRowComesFromItsOwnAttribute() {
        XCTAssertEqual(mix.headerRow, 135, "C134 + firstHeaderRow 1")
    }

    /// The data field caption sits above the header row when `firstHeaderRow` is not zero.
    func testTheCaptionRowIsTheTopOfTheRange() {
        XCTAssertEqual(mix.captionRow, 134, "`Sum of Subs` and `FME_Calc` are written here")
    }

    func testDataStartsBelowTheHeader() {
        XCTAssertEqual(mix.firstDataSheetRow, 136, "C134 + firstDataRow 2")
    }

    /// **Page fields are rendered above the range, and one blank row separates them from it.**
    ///
    /// `rowPageCount="2"` against a range starting at 134 puts them on 131 and 132, top to
    /// bottom in listing order, leaving 133 empty. The obvious reading — the two rows directly
    /// above, 133 and 132 — is what this test first asserted, and it is wrong on **all 40**
    /// pivots in the corpus workbook that carry page fields. The separator row is real.
    func testPageFieldsSitAboveTheRangeWithABlankRowBetween() {
        XCTAssertEqual(mix.pageFieldRows, [131, 132],
                       "start - rowPageCount - 1 first, then down, matching the listing order")
        XCTAssertFalse(mix.pageFieldRows.contains(133), "the separator row holds no field")
    }

    // MARK: Columns

    /// One label column per row field, left to right in the order the file lists them.
    func testEachRowFieldOwnsOneLabelColumn() {
        XCTAssertEqual(mix.labelColumn(of: .field("Scenario")), CellRef("C1").column)
        XCTAssertEqual(mix.labelColumn(of: .field("Region")), CellRef("D1").column)
        XCTAssertEqual(mix.labelColumn(of: .field("LOBMix_noXH")), CellRef("E1").column)
        XCTAssertEqual(mix.labelColumn(of: .field("BP/IP")), CellRef("F1").column)
    }

    func testAFieldThatIsNotOnTheRowAxisHasNoLabelColumn() {
        XCTAssertNil(mix.labelColumn(of: .field("FME_Calc")), "it is a column field")
        XCTAssertNil(mix.labelColumn(of: .field("Fiber")), "it is on no axis at all")
    }

    /// `firstDataCol="4"` — the first four columns are labels, and `G` onwards is data.
    func testDataColumnsStartAfterTheLabels() {
        XCTAssertEqual(mix.firstDataSheetColumn, CellRef("G1").column)
        XCTAssertEqual(mix.dataColumns, CellRef("G1").column...CellRef("L1").column)
    }

    // MARK: The values pseudo-field

    /// **`<field x="-2"/>` is not a field.** It marks where the data field *names* are
    /// rendered, and 15 of this workbook's 50 pivots put it on the row axis — `pivotTable7`
    /// renders `Values | Scenario | Region`, where column `C` holds ` B1`, ` HSI`, ` CDV`.
    ///
    /// A `String` list would have to invent a name for it, and `"Values"` is a name a real
    /// field can have. So it is a case rather than a string.
    func testTheValuesPseudoFieldIsNotAFieldName() {
        let stacked = PivotTableLayout(
            sheet: "NED Mix",
            range: CellRange(from: CellRef("C267"), to: CellRef("K320")),
            firstHeaderRow: 1, firstDataRow: 2, firstDataCol: 3,
            dataFields: [" B1", " HSI", " CDV", "Sum of Subs"],
            dataFieldSources: ["B1", "HSI", "CDV", "Subs"],
            rowFields: [.dataFieldNames, .field("Scenario"), .field("Region")],
            columnFields: [.field("FME_Calc")],
            pageFields: ["SalesChannelRollUp", "ActivityDetail"],
            pageFieldRowCount: 2,
            hasRowGrandTotals: true, hasColumnGrandTotals: true)

        XCTAssertEqual(stacked.labelColumn(of: .dataFieldNames), CellRef("C1").column,
                       "the leftmost label column holds the data field names")
        XCTAssertEqual(stacked.labelColumn(of: .field("Scenario")), CellRef("D1").column)
        XCTAssertNil(stacked.labelColumn(of: .field("Values")),
                     "a field really named `Values` is not the pseudo-field")
    }

    // MARK: Naming a data field

    /// **Excel accepts the caption or the source field name**, and the corpus needs both.
    ///
    /// The formulas ask for `"Subs"`; the file writes `<dataField name="Sum of Subs" fld="11"/>`
    /// over cache field 11, `Subs`. Matching captions alone refuses all 3,574.
    func testADataFieldAnswersToItsCaptionAndItsSourceName() {
        XCTAssertEqual(mix.dataFieldIndex(named: "Sum of Subs"), 0, "the caption")
        XCTAssertEqual(mix.dataFieldIndex(named: "Subs"), 0, "the source field")
        XCTAssertNil(mix.dataFieldIndex(named: "Sum of Nothing"))
    }

    /// Field names are matched **case-insensitively**, which the corpus forces.
    ///
    /// The cache spells the field `week ending`; every formula writes `"Week Ending"`. 892
    /// cells at one anchor alone turn on this.
    func testNamesAreMatchedWithoutRegardToCase() {
        XCTAssertEqual(mix.dataFieldIndex(named: "sum of subs"), 0)
        XCTAssertEqual(mix.labelColumn(of: .field("scenario")), CellRef("C1").column)
    }

    /// **Not trimmed, though.** Three captions in the corpus workbook are written with a
    /// leading space — `" B1"`, `" HSI"`, `" CDV"` — and a helpful trim is how a lookup starts
    /// answering a column nobody asked for.
    func testNamesAreNotTrimmed() {
        let stacked = PivotTableLayout(
            sheet: "S", range: CellRange(from: CellRef("A1"), to: CellRef("D9")),
            firstHeaderRow: 0, firstDataRow: 1, firstDataCol: 1,
            dataFields: [" B1", "B1"], dataFieldSources: ["B1x", "B1"],
            rowFields: [], columnFields: [], pageFields: [], pageFieldRowCount: 0,
            hasRowGrandTotals: true, hasColumnGrandTotals: true)
        XCTAssertEqual(stacked.dataFieldIndex(named: " B1"), 0, "the spaced caption")
        XCTAssertEqual(stacked.dataFieldIndex(named: "B1"), 1, "and the unspaced one, separately")
    }
}
