import Foundation

/// A unified cell value type matching Excel's value semantics.
public enum CellValue: Equatable, Hashable, Sendable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case error(ExcelError)
    indirect case formula(FormulaAST, cached: CellValue?)
    case date(Date)
    case blank
    /// A rectangle of values, keeping its own dimensions.
    ///
    /// Shaped rather than flat: see ``CellMatrix`` for why a range that forgets
    /// its width cannot be read back correctly.
    indirect case array(CellMatrix)

    /// A function: the names it takes, what it computes, and what it closed over.
    ///
    /// `LAMBDA` makes a function a first-class value, and three legal Excel shapes cannot be
    /// expressed without one — a lambda **returned** by a lambda, **bound** by a `LET`, or
    /// **chosen** by an `IF`. Each of them would otherwise evaluate to something plausible
    /// rather than to an error, which is the failure a workbook checker cannot afford.
    ///
    /// ## `captured` is not decoration
    ///
    /// The first design had parameters and a body and nothing else, and that was an error
    /// rather than a simplification. `LAMBDA(x, LAMBDA(y, x+y))` returns a function that must
    /// remember `x`. A lambda with no captured frame is not a closure, and currying does not
    /// fail loudly under one — it silently returns the wrong answer.
    ///
    /// ## Parameter names are kept as the formula spells them
    ///
    /// Excel writes `_xlpm.` on a parameter's declaration and on every use, so the prefix
    /// matches itself and nothing needs to understand it. Stripping it would let a parameter
    /// collide with a workbook name that differs only by the prefix, and depending on its
    /// presence would break on any file Excel did not write.
    indirect case lambda(parameters: [String], body: FormulaAST, captured: [String: CellValue])

    /// The resolved value; returns cached value for formulas, self otherwise.
    public var resolved: CellValue {
        switch self {
        case .formula(_, let cached):
            return cached ?? .blank
        default:
            return self
        }
    }

    /// Whether this value is a formula.
    public var isFormula: Bool {
        if case .formula = self { return true }
        return false
    }

    /// The formula AST if this is a formula value, nil otherwise.
    public var formulaAST: FormulaAST? {
        if case .formula(let ast, _) = self { return ast }
        return nil
    }
}
