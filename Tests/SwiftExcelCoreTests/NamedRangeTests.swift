import XCTest
@testable import SwiftExcelCore

final class NamedRangeTests: XCTestCase {

    // MARK: - NamedRange Construction

    func testCreateWithCellTarget() {
        let range = NamedRange(
            name: "Rate",
            reference: .cell(CellRef("B5"))
        )
        XCTAssertEqual(range.name, "Rate")
        XCTAssertEqual(range.scope, .workbook)
        if case .cell(let ref) = range.reference {
            XCTAssertEqual(ref.column, 2)
            XCTAssertEqual(ref.row, 5)
        } else {
            XCTFail("Expected .cell target")
        }
    }

    func testCreateWithRangeTarget() {
        let range = NamedRange(
            name: "Data",
            reference: .range(CellRange("A1:A100"))
        )
        XCTAssertEqual(range.name, "Data")
        if case .range(let cellRange) = range.reference {
            XCTAssertEqual(cellRange.start.column, 1)
            XCTAssertEqual(cellRange.start.row, 1)
            XCTAssertEqual(cellRange.end.column, 1)
            XCTAssertEqual(cellRange.end.row, 100)
        } else {
            XCTFail("Expected .range target")
        }
    }

    func testCreateWithSheetScope() {
        let range = NamedRange(
            name: "Total",
            reference: .cell(CellRef("D10")),
            scope: .sheet("Summary")
        )
        XCTAssertEqual(range.name, "Total")
        XCTAssertEqual(range.scope, .sheet("Summary"))
    }

    func testCreateWithFormulaTarget() {
        let range = NamedRange(
            name: "Dynamic",
            reference: .formula(
                .function("OFFSET", [
                    .cellRef(CellRef("A1")),
                    .number(0),
                    .number(0),
                    .function("COUNTA", [.cellRef(CellRef("A1"))]),
                ])
            )
        )
        XCTAssertEqual(range.name, "Dynamic")
        if case .formula(let expr) = range.reference {
            if case .function(let name, let args) = expr {
                XCTAssertEqual(name, "OFFSET")
                XCTAssertEqual(args.count, 4)
            } else {
                XCTFail("Expected .function expression")
            }
        } else {
            XCTFail("Expected .formula target")
        }
    }

    func testEquatable() {
        let a = NamedRange(
            name: "Rate",
            reference: .cell(CellRef("B5")),
            scope: .workbook
        )
        let b = NamedRange(
            name: "Rate",
            reference: .cell(CellRef("B5")),
            scope: .workbook
        )
        XCTAssertEqual(a, b)
    }

    func testNotEqualDifferentName() {
        let a = NamedRange(name: "Rate", reference: .cell(CellRef("B5")))
        let b = NamedRange(name: "Discount", reference: .cell(CellRef("B5")))
        XCTAssertNotEqual(a, b)
    }

    func testNotEqualDifferentTarget() {
        let a = NamedRange(name: "Rate", reference: .cell(CellRef("B5")))
        let b = NamedRange(name: "Rate", reference: .cell(CellRef("C5")))
        XCTAssertNotEqual(a, b)
    }

    func testNotEqualDifferentScope() {
        let a = NamedRange(name: "Rate", reference: .cell(CellRef("B5")), scope: .workbook)
        let b = NamedRange(name: "Rate", reference: .cell(CellRef("B5")), scope: .sheet("S1"))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - NamedRangeCollection: Add and Count

    func testAddAndCount() {
        var collection = NamedRangeCollection()
        XCTAssertEqual(collection.count, 0)

        collection.add(NamedRange(name: "Rate", reference: .cell(CellRef("B5"))))
        XCTAssertEqual(collection.count, 1)

        collection.add(NamedRange(name: "Total", reference: .cell(CellRef("D10"))))
        XCTAssertEqual(collection.count, 2)
    }

    func testInitWithArray() {
        let collection = NamedRangeCollection([
            NamedRange(name: "A", reference: .cell(CellRef("A1"))),
            NamedRange(name: "B", reference: .cell(CellRef("B1"))),
        ])
        XCTAssertEqual(collection.count, 2)
    }

    func testAllProperty() {
        let ranges = [
            NamedRange(name: "A", reference: .cell(CellRef("A1"))),
            NamedRange(name: "B", reference: .cell(CellRef("B1"))),
        ]
        let collection = NamedRangeCollection(ranges)
        XCTAssertEqual(collection.all.count, 2)
        XCTAssertEqual(collection.all[0].name, "A")
        XCTAssertEqual(collection.all[1].name, "B")
    }

    // MARK: - NamedRangeCollection: Resolve

    func testResolveWorkbookScopedName() {
        var collection = NamedRangeCollection()
        collection.add(NamedRange(name: "Rate", reference: .cell(CellRef("B5"))))

        let result = collection.resolve("Rate")
        XCTAssertNotNil(result)
        if case .cell(let ref) = result {
            XCTAssertEqual(ref.column, 2)
            XCTAssertEqual(ref.row, 5)
        } else {
            XCTFail("Expected .cell(B5)")
        }
    }

    func testResolveReturnsNilForUnknownName() {
        let collection = NamedRangeCollection()
        XCTAssertNil(collection.resolve("DoesNotExist"))
    }

    func testResolveCaseInsensitiveLowercase() {
        var collection = NamedRangeCollection()
        collection.add(NamedRange(name: "Rate", reference: .cell(CellRef("B5"))))

        let result = collection.resolve("rate")
        XCTAssertNotNil(result)
        if case .cell(let ref) = result {
            XCTAssertEqual(ref.column, 2)
            XCTAssertEqual(ref.row, 5)
        } else {
            XCTFail("Expected .cell(B5)")
        }
    }

    func testResolveCaseInsensitiveUppercase() {
        var collection = NamedRangeCollection()
        collection.add(NamedRange(name: "Rate", reference: .cell(CellRef("B5"))))

        let result = collection.resolve("RATE")
        XCTAssertNotNil(result)
        if case .cell(let ref) = result {
            XCTAssertEqual(ref.column, 2)
            XCTAssertEqual(ref.row, 5)
        } else {
            XCTFail("Expected .cell(B5)")
        }
    }

    func testScopePrecedenceSheetOverWorkbook() {
        var collection = NamedRangeCollection()
        collection.add(NamedRange(
            name: "Total",
            reference: .cell(CellRef("D10")),
            scope: .workbook
        ))
        collection.add(NamedRange(
            name: "Total",
            reference: .cell(CellRef("E10")),
            scope: .sheet("Summary")
        ))

        let result = collection.resolve("Total", inSheet: "Summary")
        XCTAssertNotNil(result)
        if case .cell(let ref) = result {
            XCTAssertEqual(ref.reference, "E10")
        } else {
            XCTFail("Expected .cell(E10) from sheet scope")
        }
    }

    func testScopeFallbackToWorkbook() {
        var collection = NamedRangeCollection()
        collection.add(NamedRange(
            name: "Total",
            reference: .cell(CellRef("D10")),
            scope: .workbook
        ))
        collection.add(NamedRange(
            name: "Total",
            reference: .cell(CellRef("E10")),
            scope: .sheet("Summary")
        ))

        let result = collection.resolve("Total", inSheet: "Other")
        XCTAssertNotNil(result)
        if case .cell(let ref) = result {
            XCTAssertEqual(ref.reference, "D10")
        } else {
            XCTFail("Expected .cell(D10) from workbook scope")
        }
    }

    func testScopeNoSheetFallsBackToWorkbook() {
        var collection = NamedRangeCollection()
        collection.add(NamedRange(
            name: "Total",
            reference: .cell(CellRef("D10")),
            scope: .workbook
        ))
        collection.add(NamedRange(
            name: "Total",
            reference: .cell(CellRef("E10")),
            scope: .sheet("Summary")
        ))

        let result = collection.resolve("Total")
        XCTAssertNotNil(result)
        if case .cell(let ref) = result {
            XCTAssertEqual(ref.reference, "D10")
        } else {
            XCTFail("Expected .cell(D10) from workbook scope")
        }
    }

    func testResolveMultipleNames() {
        var collection = NamedRangeCollection()
        collection.add(NamedRange(name: "Rate", reference: .cell(CellRef("B5"))))
        collection.add(NamedRange(name: "Revenue", reference: .cell(CellRef("C3"))))
        collection.add(NamedRange(
            name: "Data",
            reference: .range(CellRange("A1:A100"))
        ))

        let rate = collection.resolve("Rate")
        XCTAssertNotNil(rate)
        if case .cell(let ref) = rate {
            XCTAssertEqual(ref.reference, "B5")
        } else {
            XCTFail("Expected .cell for Rate")
        }

        let revenue = collection.resolve("Revenue")
        XCTAssertNotNil(revenue)
        if case .cell(let ref) = revenue {
            XCTAssertEqual(ref.reference, "C3")
        } else {
            XCTFail("Expected .cell for Revenue")
        }

        let data = collection.resolve("Data")
        XCTAssertNotNil(data)
        if case .range(let range) = data {
            XCTAssertEqual(range.start.reference, "A1")
            XCTAssertEqual(range.end.reference, "A100")
        } else {
            XCTFail("Expected .range for Data")
        }
    }

    // MARK: - NameResolver Protocol

    func testNamedRangeCollectionConformsToNameResolver() {
        var collection = NamedRangeCollection()
        collection.add(NamedRange(name: "Rate", reference: .cell(CellRef("B5"))))

        let resolver: any NameResolver = collection
        let result = resolver.resolve("Rate", inSheet: nil)
        XCTAssertNotNil(result)
    }

    func testNameResolverAsParameter() {
        var collection = NamedRangeCollection()
        collection.add(NamedRange(name: "Rate", reference: .cell(CellRef("B5"))))

        let result = resolveUsingProtocol(resolver: collection, name: "Rate")
        XCTAssertNotNil(result)
    }

    // MARK: - Helpers

    private func resolveUsingProtocol(
        resolver: some NameResolver,
        name: String
    ) -> NamedRangeTarget? {
        resolver.resolve(name, inSheet: nil)
    }
}

// MARK: - What a file says, not only what an evaluator needs

/// The parts of a name that exist so a workbook can be written back as it was read.
///
/// `PROPOSAL_defined_names.md` (SwiftExcelFunctions) chose to hold a name **once** — the
/// target is the name's meaning, and a writer reproduces the refers-to text from it rather
/// than keeping a copy alongside. These tests pin the two things that decision needs from
/// this type: a target that can admit it did not understand, and the attributes a round trip
/// would otherwise drop.
final class NamedRangeFidelityTests: XCTestCase {

    /// `.unparsed` is exact by construction: reproducing it is the identity.
    ///
    /// This is what makes reconstruction safe at all. Anything the reader cannot prove it can
    /// reproduce goes here, so byte-exactness is available for every name from the start and
    /// each parsed shape is an opt-in promise rather than a hope.
    func testUnparsedKeepsItsTextExactly() {
        let shapes = [
            "Expenditures!$D:$D",
            "'2018 - Sorted by Area'!$J$2:$J$333",
            "_xlfn.LAMBDA(_xlpm.x,_xlpm.x+1)",
            "OFFSET(Sheet1!$A$1,0,0,COUNTA(Sheet1!$A:$A),1)",
        ]
        for text in shapes {
            guard case .unparsed(let kept) = NamedRangeTarget.unparsed(text) else {
                return XCTFail("expected .unparsed for \(text)")
            }
            XCTAssertEqual(kept, text)
        }
    }

    /// `.unparsed` is a different statement from `.formula(.text(…))`, which is the point.
    ///
    /// The old fallback claimed a name **was** a text constant. The two must not compare
    /// equal, or a reader could keep making the old claim and nothing would notice.
    func testUnparsedIsNotATextConstant() {
        XCTAssertNotEqual(NamedRangeTarget.unparsed("42"),
                          NamedRangeTarget.formula(.text("42")))
        XCTAssertNotEqual(NamedRangeTarget.unparsed("Expenditures!$D:$D"),
                          NamedRangeTarget.formula(.text("Expenditures!$D:$D")))
    }

    /// Hidden is 46% of the names in a real corpus, so it is carried rather than inferred.
    func testHiddenAndAttributesSurvive() {
        let filter = NamedRange(
            name: "_xlnm._FilterDatabase",
            reference: .unparsed("Expenditures!$A$2:$W$2446"),
            scope: .sheet("Expenditures"),
            isHidden: true,
            attributes: ["comment": "set by the filter"])

        XCTAssertTrue(filter.isHidden)
        XCTAssertEqual(filter.attributes["comment"], "set by the filter")
        XCTAssertEqual(filter.scope, .sheet("Expenditures"))
    }

    /// The defaults keep every existing caller compiling and behaving as before.
    func testAPlainNameIsVisibleAndUnadorned() {
        let name = NamedRange(name: "rate", reference: .cell(CellRef("B1")))
        XCTAssertFalse(name.isHidden)
        XCTAssertTrue(name.attributes.isEmpty)
        XCTAssertEqual(name.scope, .workbook)
    }

    /// Two names differing only in what a round trip would drop are not the same name.
    ///
    /// `Equatable` is what a fidelity test compares, so if `isHidden` were left out of it, a
    /// round-trip check would pass while un-hiding half a workbook.
    func testEqualityNoticesTheFidelityFields() {
        let visible = NamedRange(name: "n", reference: .cell(CellRef("A1")))
        let hidden = NamedRange(name: "n", reference: .cell(CellRef("A1")), isHidden: true)
        let annotated = NamedRange(name: "n", reference: .cell(CellRef("A1")),
                                   attributes: ["description": "x"])
        XCTAssertNotEqual(visible, hidden)
        XCTAssertNotEqual(visible, annotated)
    }
}
