import XCTest
@testable import SwiftExcelCore

/// The graph built from a provider and an explicit cell set.
///
/// These exercise it with no workbook anywhere — a plain in-memory provider — which
/// is what moving the type here exists to enable.
final class DependencyGraphTests: XCTestCase {

    /// A sheet held in a dictionary. No file, no format, no workbook.
    private struct Sheet: CellValueProvider {
        var cells: [CellAddress: CellValue]
        func value(at ref: CellRef) -> CellValue? { value(at: ref, inSheet: "Model") }
        func value(at ref: CellRef, inSheet: String) -> CellValue? {
            cells[CellAddress(sheet: inSheet, cell: ref)]
        }
        func lastPopulatedCell() -> CellRef? { nil }
        func lastPopulatedCell(inSheet: String) -> CellRef? { nil }
        func values(in range: CellRange) -> [CellValue] { [] }
        func values(in range: CellRange, inSheet: String) -> [CellValue] { [] }
    }

    private func address(_ ref: String, _ sheet: String = "Model") -> CellAddress {
        CellAddress(sheet: sheet, ref: ref)
    }

    /// `B1 = A1 * 2`, `C1 = B1 + A1`.
    private func chain() -> Sheet {
        Sheet(cells: [
            address("A1"): .number(10),
            address("B1"): .formula(.multiply(.cellRef(CellRef("A1")),
                                              .number(2)), cached: nil),
            address("C1"): .formula(.add(.cellRef(CellRef("B1")),
                                         .cellRef(CellRef("A1"))),
                                    cached: nil),
        ])
    }

    // MARK: - The order

    /// A precedent always orders before its dependent.
    func testTheOrderPutsPrecedentsFirst() {
        let sheet = chain()
        let graph = DependencyGraph(cells: Array(sheet.cells.keys), provider: sheet)
        let order = graph.evaluationOrder.map(\.cell.reference)
        XCTAssertEqual(order.count, 3)
        guard let a = order.firstIndex(of: "A1"),
              let b = order.firstIndex(of: "B1"),
              let c = order.firstIndex(of: "C1") else {
            return XCTFail("expected all three cells, got \(order)")
        }
        XCTAssertLessThan(a, b, "A1 feeds B1")
        XCTAssertLessThan(b, c, "B1 feeds C1")
    }

    /// **The order does not depend on the order the addresses arrive in.**
    ///
    /// This initialiser is the first to hand the graph a container whose iteration
    /// order is unspecified, so the property is newly worth pinning. Everything
    /// downstream leans on it: a nondeterministic order would silently break seeded
    /// reproducibility, which for a trial loop means same seed, same numbers, or the
    /// design is decoration.
    func testTheOrderIsIndependentOfTheInputOrder() {
        let sheet = chain()
        let forward = Array(sheet.cells.keys).sorted { $0.sortKey < $1.sortKey }
        let backward = Array(forward.reversed())

        let one = DependencyGraph(cells: forward, provider: sheet).evaluationOrder
        let two = DependencyGraph(cells: backward, provider: sheet).evaluationOrder
        XCTAssertEqual(one, two, "the same cells in a different sequence must order identically")
    }

    // MARK: - Scope

    /// `CellAddress` carries its sheet, so a cross-sheet precedent orders correctly
    /// with no scoping parameter at all.
    func testACrossSheetPrecedentOrdersFirst() {
        let sheet = Sheet(cells: [
            address("A1", "Inputs"): .number(5),
            address("B1", "Model"): .formula(
                .sheetRef(SheetReference(sheet: "Inputs",
                                         range: CellRange(from: CellRef(column: 1, row: 1),
                                                          to: CellRef(column: 1, row: 1)))),
                cached: nil),
        ])
        let graph = DependencyGraph(cells: Array(sheet.cells.keys), provider: sheet)
        let order = graph.evaluationOrder
        guard let input = order.firstIndex(of: address("A1", "Inputs")),
              let model = order.firstIndex(of: address("B1", "Model")) else {
            return XCTFail("expected both cells, got \(order.map(\.sortKey))")
        }
        XCTAssertLessThan(input, model, "Inputs!A1 feeds Model!B1")
    }

    /// `sheetScope` drops a reference onto another sheet along with its edge — the
    /// behaviour `init(sheet:including:)` is built on.
    func testSheetScopeDropsAForeignReference() {
        let sheet = Sheet(cells: [
            address("A1", "Inputs"): .number(5),
            address("B1", "Model"): .formula(
                .sheetRef(SheetReference(sheet: "Inputs",
                                         range: CellRange(from: CellRef(column: 1, row: 1),
                                                          to: CellRef(column: 1, row: 1)))),
                cached: nil),
        ])
        let graph = DependencyGraph(cells: Array(sheet.cells.keys), provider: sheet,
                                    sheetScope: ["Model"])
        XCTAssertTrue(graph.precedents(of: address("B1", "Model")).isEmpty,
                      "a reference off the scoped sheet is dropped with its edge")
    }

    // MARK: - Cycles

    /// A cycle is detected and reported rather than silently truncating the order.
    func testACycleIsDetected() {
        let sheet = Sheet(cells: [
            address("A1"): .formula(.cellRef(CellRef("B1")),
                                    cached: nil),
            address("B1"): .formula(.cellRef(CellRef("A1")),
                                    cached: nil),
        ])
        let graph = DependencyGraph(cells: Array(sheet.cells.keys), provider: sheet)
        XCTAssertFalse(graph.isAcyclic)
        XCTAssertFalse(graph.cycles.isEmpty)
        XCTAssertTrue(graph.evaluationOrder.isEmpty, "a cycle leaves nothing safely orderable")
    }

    /// A cycle that closes across two sheets is still a cycle.
    func testACycleAcrossTwoSheetsIsDetected() {
        let sheet = Sheet(cells: [
            address("A1", "One"): .formula(
                .sheetRef(SheetReference(sheet: "Two",
                                         range: CellRange(from: CellRef(column: 1, row: 1),
                                                          to: CellRef(column: 1, row: 1)))),
                cached: nil),
            address("A1", "Two"): .formula(
                .sheetRef(SheetReference(sheet: "One",
                                         range: CellRange(from: CellRef(column: 1, row: 1),
                                                          to: CellRef(column: 1, row: 1)))),
                cached: nil),
        ])
        let graph = DependencyGraph(cells: Array(sheet.cells.keys), provider: sheet)
        XCTAssertFalse(graph.isAcyclic)
    }

    // MARK: - Inputs and outputs

    /// A cell with no precedents is an input; one with no dependents is an output.
    func testInputsAndOutputs() {
        let sheet = chain()
        let graph = DependencyGraph(cells: Array(sheet.cells.keys), provider: sheet)
        XCTAssertEqual(graph.inputs.map(\.cell.reference), ["A1"])
        XCTAssertEqual(graph.outputs.map(\.cell.reference), ["C1"])
    }

    /// An empty cell set is a graph with nothing in it, not a trap.
    func testAnEmptyCellSetIsAnEmptyGraph() {
        let graph = DependencyGraph(cells: [], provider: Sheet(cells: [:]))
        XCTAssertTrue(graph.allCells.isEmpty)
        XCTAssertTrue(graph.evaluationOrder.isEmpty)
        XCTAssertTrue(graph.isAcyclic, "nothing cannot contain a cycle")
    }
}
