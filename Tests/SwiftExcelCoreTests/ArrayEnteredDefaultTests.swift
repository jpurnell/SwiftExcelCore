import XCTest
@testable import SwiftExcelCore

/// ``CellValueProvider/isArrayEntered(at:inSheet:)`` and its default.
///
/// The flag distinguishes two readings of the same formula text. Array-entered, a range means
/// the whole range; normally entered, Excel **implicitly intersects** it against the formula's
/// own row or column where a single value is expected. Measured across 300 corpus workbooks,
/// **256 of 2,588,513 formulas carry it** — rare, and decisive wherever it appears.
///
/// The default is `false`, which keeps the addition additive in the way `sheetNames()` and
/// `pivotTables()` already are: every existing conformance compiles unchanged and reports what
/// is overwhelmingly the common case.
final class ArrayEnteredDefaultTests: XCTestCase {

    /// A provider written before this existed, which is most of them.
    private struct Plain: CellValueProvider {
        func value(at ref: CellRef) -> CellValue? { nil }
        func value(at ref: CellRef, inSheet: String) -> CellValue? { nil }
        func lastPopulatedCell() -> CellRef? { nil }
        func lastPopulatedCell(inSheet: String) -> CellRef? { nil }
        func values(in range: CellRange) -> [CellValue] { [] }
        func values(in range: CellRange, inSheet: String) -> [CellValue] { [] }
    }

    /// One that reads a file and knows.
    private struct Reader: CellValueProvider {
        let entered: Set<String>
        func value(at ref: CellRef) -> CellValue? { nil }
        func value(at ref: CellRef, inSheet: String) -> CellValue? { nil }
        func lastPopulatedCell() -> CellRef? { nil }
        func lastPopulatedCell(inSheet: String) -> CellRef? { nil }
        func values(in range: CellRange) -> [CellValue] { [] }
        func values(in range: CellRange, inSheet: String) -> [CellValue] { [] }
        func isArrayEntered(at ref: CellRef, inSheet sheet: String) -> Bool {
            entered.contains(ref.reference)
        }
    }

    func testTheDefaultIsNotArrayEntered() {
        XCTAssertFalse(Plain().isArrayEntered(at: CellRef("A1"), inSheet: "Sheet1"),
                       "a provider that reads no file reports the common case")
    }

    func testAProviderThatKnowsAnswersForItself() {
        let reader = Reader(entered: ["AF14"])
        XCTAssertTrue(reader.isArrayEntered(at: CellRef("AF14"), inSheet: "Template"))
        XCTAssertFalse(reader.isArrayEntered(at: CellRef("AF15"), inSheet: "Template"))
    }
}
