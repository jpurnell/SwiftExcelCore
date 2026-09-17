import XCTest
@testable import SwiftExcelCore

/// A cell value can be a function.
///
/// `LAMBDA` makes a function a first-class value in Excel, and a type that cannot hold one
/// cannot express what a workbook contains. The three shapes that force the case:
///
/// ```
/// LAMBDA(x, LAMBDA(y, x+y))     a lambda returned by a lambda
/// LET(f, LAMBDA(x, x*2), f(3))  a lambda bound to a name
/// IF(flag, LAMBDA(x,x), …)      a lambda chosen by a formula
/// ```
///
/// All three are legal Excel. Without this case each of them evaluates to something
/// *plausible* rather than to an error, which is the failure a checker cannot afford: it
/// reports on workbooks, and a class of formulas read wrongly and silently is worse than one
/// it refuses out loud. That argument is §12 of the `LAMBDA` proposal, and it is the reason
/// a shared core package takes a source-breaking change at a minor version.
final class LambdaValueTests: XCTestCase {

    private let identity = FormulaAST.namedRange("x")

    // MARK: - The case

    func testALambdaCarriesItsParametersAndBody() throws {
        let value = CellValue.lambda(parameters: ["x"], body: identity, captured: [:])
        guard case .lambda(let parameters, let body, let captured) = value else {
            return XCTFail("expected a lambda")
        }
        XCTAssertEqual(parameters, ["x"])
        XCTAssertEqual(body, identity)
        XCTAssertTrue(captured.isEmpty)
    }

    /// **The captured frame is not decoration.**
    ///
    /// The first draft of the proposal had `parameters` and `body` and nothing else, and that
    /// was an error rather than a simplification. `LAMBDA(x, LAMBDA(y, x+y))` returns a
    /// function that must remember `x`; without somewhere to keep it, currying silently
    /// returns the wrong answer. Excel supports this and people write it.
    func testALambdaRemembersWhatItClosedOver() throws {
        let inner = CellValue.lambda(
            parameters: ["y"],
            body: .add(.namedRange("x"), .namedRange("y")),
            captured: ["x": .number(10)])

        guard case .lambda(_, _, let captured) = inner else { return XCTFail("expected a lambda") }
        XCTAssertEqual(captured["x"], .number(10))
    }

    // MARK: - Conformances

    func testTwoLambdasAreEqualWhenEveryPartIs() {
        let one = CellValue.lambda(parameters: ["x"], body: identity, captured: ["a": .number(1)])
        let same = CellValue.lambda(parameters: ["x"], body: identity, captured: ["a": .number(1)])
        let otherCapture = CellValue.lambda(
            parameters: ["x"], body: identity, captured: ["a": .number(2)])
        let otherParameter = CellValue.lambda(
            parameters: ["z"], body: identity, captured: ["a": .number(1)])

        XCTAssertEqual(one, same)
        XCTAssertNotEqual(one, otherCapture, "the closure is part of what a lambda is")
        XCTAssertNotEqual(one, otherParameter)
    }

    func testALambdaHashes() {
        let one = CellValue.lambda(parameters: ["x"], body: identity, captured: [:])
        let same = CellValue.lambda(parameters: ["x"], body: identity, captured: [:])
        XCTAssertEqual(Set([one, same]).count, 1)
    }

    /// A lambda is not a formula, and `resolved` leaves it alone.
    func testALambdaIsItsOwnResolvedValue() {
        let value = CellValue.lambda(parameters: ["x"], body: identity, captured: [:])
        XCTAssertEqual(value.resolved, value)
        XCTAssertFalse(value.isFormula)
        XCTAssertNil(value.formulaAST)
    }

    // MARK: - #CALC!

    /// Excel's error for a lambda that was never called.
    ///
    /// `=LAMBDA(x, x+1)` typed into a cell is a function sitting where a value belongs, and
    /// Excel says `#CALC!` rather than showing anything. It is the newest of the error values
    /// and the one this package needed a case for.
    func testCalcIsAnError() {
        XCTAssertEqual(ExcelError.calc.rawValue, "#CALC!")
        XCTAssertEqual(ExcelError(rawValue: "#CALC!"), .calc)
        XCTAssertEqual(String(describing: ExcelError.calc), "#CALC!")
    }

    /// Every error value round-trips through its text, `#CALC!` included.
    func testEveryErrorRoundTripsThroughItsText() {
        for error in [ExcelError.value, .ref, .div0, .name, .null, .num, .na, .calc] {
            XCTAssertEqual(ExcelError(rawValue: error.rawValue), error)
        }
    }
}
