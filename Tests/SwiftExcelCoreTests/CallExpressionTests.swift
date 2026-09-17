import XCTest
@testable import SwiftExcelCore

/// A call whose callee is an expression rather than a name.
///
/// `FormulaAST.function(String, [FormulaAST])` names what it calls, which covers every formula
/// Excel had before `LAMBDA`. It does not cover this:
///
/// ```
/// LAMBDA(f, n, IF(n<=0, 0, 1 + f(f, n-1)))(LAMBDA(f, n, …), 4094)
/// ```
///
/// The immediately-invoked form, where the thing being called is written in place and has no
/// name at all. It is not a curiosity: a workbook in the corpus — someone's Monte Carlo model
/// — writes one for a Box–Muller normal draw, and the conformance workbook that measured
/// Excel's recursion limit depends on it, because a `LAMBDA` cannot call itself by name
/// without a defined name and that needs a manual step.
///
/// Currying needs it too. `add(3)(4)` calls the lambda that `add(3)` returned, and no name
/// stands between the two calls.
final class CallExpressionTests: XCTestCase {

    func testACallCarriesItsCalleeAndArguments() throws {
        let callee = FormulaAST.function("LAMBDA", [.namedRange("x"), .namedRange("x")])
        let ast = FormulaAST.call(callee, [.number(7)])

        guard case .call(let called, let arguments) = ast else {
            return XCTFail("expected a call")
        }
        XCTAssertEqual(called, callee)
        XCTAssertEqual(arguments, [.number(7)])
    }

    /// Calls nest, which is what currying is.
    func testCallsNest() throws {
        let add = FormulaAST.function("LAMBDA", [.namedRange("x"), .namedRange("x")])
        let curried = FormulaAST.call(.call(add, [.number(3)]), [.number(4)])

        guard case .call(let inner, let outer) = curried,
              case .call = inner else {
            return XCTFail("expected a call on a call")
        }
        XCTAssertEqual(outer, [.number(4)])
    }

    func testACallTakesNoArguments() {
        XCTAssertEqual(FormulaAST.call(.namedRange("f"), []),
                       FormulaAST.call(.namedRange("f"), []))
    }

    // MARK: - Conformances

    func testEqualityLooksAtBothHalves() {
        let f = FormulaAST.namedRange("f"), g = FormulaAST.namedRange("g")
        XCTAssertEqual(FormulaAST.call(f, [.number(1)]), FormulaAST.call(f, [.number(1)]))
        XCTAssertNotEqual(FormulaAST.call(f, [.number(1)]), FormulaAST.call(g, [.number(1)]))
        XCTAssertNotEqual(FormulaAST.call(f, [.number(1)]), FormulaAST.call(f, [.number(2)]))
    }

    func testACallHashes() {
        let one = FormulaAST.call(.namedRange("f"), [.number(1)])
        let same = FormulaAST.call(.namedRange("f"), [.number(1)])
        XCTAssertEqual(Set([one, same]).count, 1)
    }

    /// A call is not a `.function`, and code that matches one must not match the other.
    ///
    /// `FunctionRegistry.canonical` and every `case .function(let name, _)` in the packages
    /// downstream key off a name. A call has none, and quietly presenting it as `.function("")`
    /// would make all of them wrong in the same silent way.
    func testACallIsNotAFunction() {
        let ast = FormulaAST.call(.namedRange("f"), [])
        if case .function = ast { XCTFail("a call is not a named function") }
    }
}
