import XCTest
@testable import SwiftExcelCore

/// A reference that spans sheets — `'Q1:Q4'!B7`, Excel's 3-D reference.
///
/// **A corpus run found 9,958 cells of one workbook depending on this**, every one a sum
/// across a span of sheets: `SUM('8887997613:8887997618'!DL62)`. This package answered 28
/// where Excel answered 47, because a span was never a thing it could express — and the
/// shortfall was silent, since the terms that *were* single sheets resolved perfectly well.
///
/// The span is already carried: a parser reading `'first:last'!A1` puts `first:last` in
/// ``SheetReference/sheetName`` whole. Excel forbids `:` in a sheet name — it is one of the
/// seven characters a sheet may not contain — so splitting on it is unambiguous rather than
/// a guess about someone's naming.
final class SheetSpanTests: XCTestCase {

    // MARK: - Recognising one

    func testASpanIsReadFromTheName() {
        let reference = SheetReference(sheet: "Q1:Q4", cell: CellRef("B7"))
        guard let span = reference.span else { return XCTFail("no span read") }
        XCTAssertEqual(span.first, "Q1")
        XCTAssertEqual(span.last, "Q4")
    }

    func testAnOrdinarySheetHasNoSpan() {
        XCTAssertNil(SheetReference(sheet: "Summary", cell: CellRef("A1")).span,
                     "a name without a colon spans nothing")
    }

    func testASheetNamedForOneSheetOnEachSideIsStillOneSpan() {
        // The corpus's own shape: names that are digits, which is what an account number
        // looks like when someone makes a sheet per account.
        let reference = SheetReference(sheet: "8887997613:8887997618", cell: CellRef("DL62"))
        XCTAssertEqual(reference.span?.first, "8887997613")
        XCTAssertEqual(reference.span?.last, "8887997618")
    }

    /// A malformed span is not a span, and must not read as half of one.
    func testAnEmptySideIsNotASpan() {
        XCTAssertNil(SheetReference(sheet: ":Q4", cell: CellRef("A1")).span)
        XCTAssertNil(SheetReference(sheet: "Q1:", cell: CellRef("A1")).span)
        XCTAssertNil(SheetReference(sheet: ":", cell: CellRef("A1")).span)
        XCTAssertNil(SheetReference(sheet: "Q1:Q2:Q3", cell: CellRef("A1")).span,
                     "two colons is not a name Excel can produce, and is not guessed at")
    }

    // MARK: - Expanding one

    private struct Book: CellValueProvider {
        let sheets: [String]
        func value(at ref: CellRef) -> CellValue? { nil }
        func value(at ref: CellRef, inSheet: String) -> CellValue? { nil }
        func lastPopulatedCell() -> CellRef? { nil }
        func lastPopulatedCell(inSheet: String) -> CellRef? { nil }
        func values(in range: CellRange) -> [CellValue] { [] }
        func values(in range: CellRange, inSheet: String) -> [CellValue] { [] }
        func sheetNames() -> [String] { sheets }
    }

    /// A span covers the sheets *positionally* between its ends, which is why order matters
    /// and why a provider has to say what it is.
    func testASpanCoversEverySheetBetweenItsEnds() {
        let book = Book(sheets: ["Cover", "Q1", "Q2", "Q3", "Q4", "Notes"])
        let reference = SheetReference(sheet: "Q1:Q4", cell: CellRef("B7"))
        XCTAssertEqual(reference.sheets(in: book), ["Q1", "Q2", "Q3", "Q4"],
                       "the ends included, and `Cover` and `Notes` outside it left out")
    }

    func testASpanWrittenBackwardsStillCoversTheSheetsBetween() {
        let book = Book(sheets: ["Cover", "Q1", "Q2", "Q3", "Q4"])
        XCTAssertEqual(SheetReference(sheet: "Q4:Q1", cell: CellRef("B7")).sheets(in: book),
                       ["Q1", "Q2", "Q3", "Q4"],
                       "Excel reads the pair as a span, not as a direction")
    }

    func testASpanOfOneSheetIsThatSheet() {
        let book = Book(sheets: ["Q1", "Q2"])
        XCTAssertEqual(SheetReference(sheet: "Q1:Q1", cell: CellRef("A1")).sheets(in: book),
                       ["Q1"])
    }

    /// An end that names no sheet spans nothing.
    ///
    /// **Not an error and not a guess** — the same choice the provider already makes for an
    /// absent sheet, which reads as blanks rather than failing. A run that silently dropped
    /// to one end of the span would be the 28-instead-of-47 bug again, wearing a new face.
    func testAnEndThatNamesNoSheetSpansNothing() {
        let book = Book(sheets: ["Q1", "Q2"])
        XCTAssertEqual(SheetReference(sheet: "Q1:Q9", cell: CellRef("A1")).sheets(in: book), [])
        XCTAssertEqual(SheetReference(sheet: "Q0:Q2", cell: CellRef("A1")).sheets(in: book), [])
    }

    func testAnOrdinarySheetExpandsToItself() {
        let book = Book(sheets: ["Summary", "Q1"])
        XCTAssertEqual(SheetReference(sheet: "Summary", cell: CellRef("A1")).sheets(in: book),
                       ["Summary"], "no colon, so the reference is its own single sheet")
    }

    /// A provider that does not model a workbook has no order to give.
    ///
    /// The default returns none, which keeps the addition additive: every existing conformance
    /// compiles and behaves exactly as it did, and a 3-D reference over such a provider reads
    /// as empty rather than failing.
    func testAProviderWithoutSheetsReportsNone() {
        struct Bare: CellValueProvider {
            func value(at ref: CellRef) -> CellValue? { nil }
            func value(at ref: CellRef, inSheet: String) -> CellValue? { nil }
            func lastPopulatedCell() -> CellRef? { nil }
            func lastPopulatedCell(inSheet: String) -> CellRef? { nil }
            func values(in range: CellRange) -> [CellValue] { [] }
            func values(in range: CellRange, inSheet: String) -> [CellValue] { [] }
        }
        XCTAssertEqual(Bare().sheetNames(), [])
        XCTAssertEqual(SheetReference(sheet: "Q1:Q4", cell: CellRef("A1")).sheets(in: Bare()), [])
    }
}
