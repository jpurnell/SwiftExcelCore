/// A recursive AST representing an Excel formula expression.
public indirect enum FormulaAST: Equatable, Hashable, Sendable {

    // Leaf nodes
    case cellRef(CellRef)
    case cellRange(CellRange)
    case sheetRef(SheetReference)
    case namedRange(String)
    case number(Double)
    case text(String)
    case bool(Bool)
    case error(ExcelError)

    /// An argument that is not there.
    ///
    /// `IFERROR(B5/C5-1,)` leaves its second argument out, and
    /// `ADDRESS(row, col, 1, , "Sheet")` leaves out its fourth: the comma still
    /// marks the place, because position decides which parameter is which.
    /// Excel's own binary grammar has a token for exactly this — `ptgMissArg`.
    ///
    /// It is its own case because nothing else says the same thing. `0` and `""`
    /// are values a formula could have supplied deliberately, and substituting
    /// either would report that the sheet said something it did not. What a
    /// function does with an omitted argument is the function's business: `ADDRESS`
    /// treats it as a default, and a defaulted argument is not the same as a
    /// zero one.
    ///
    /// Measured across 79 workbooks, about 21,500 formulas need this.
    case missing

    // Arithmetic
    case add(FormulaAST, FormulaAST)
    case subtract(FormulaAST, FormulaAST)
    case multiply(FormulaAST, FormulaAST)
    case divide(FormulaAST, FormulaAST)
    case power(FormulaAST, FormulaAST)
    case negate(FormulaAST)
    case concatenate(FormulaAST, FormulaAST)

    // Comparison
    case equal(FormulaAST, FormulaAST)
    case notEqual(FormulaAST, FormulaAST)
    case greaterThan(FormulaAST, FormulaAST)
    case lessThan(FormulaAST, FormulaAST)
    case greaterOrEqual(FormulaAST, FormulaAST)
    case lessOrEqual(FormulaAST, FormulaAST)

    // Function call
    case function(String, [FormulaAST])

    /// A call whose callee is an expression rather than a name.
    ///
    /// ``function(_:_:)`` names what it calls, which covers every formula Excel had before
    /// `LAMBDA`. It does not cover the immediately-invoked form, where the thing being called
    /// is written in place:
    ///
    /// ```
    /// LAMBDA(f, n, IF(n<=0, 0, 1 + f(f, n-1)))(LAMBDA(f, n, …), 4094)
    /// ```
    ///
    /// That is not a curiosity. A `LAMBDA` cannot call itself by name without a defined name,
    /// and a defined name is a manual step — so self-application is how a recursive lambda is
    /// written without one, and it is what the conformance workbook used to measure Excel's
    /// 4,096-invocation limit. A workbook in the corpus writes one for a Box–Muller normal
    /// draw, which is how we know Excel accepts the form.
    ///
    /// Currying needs it too: `add(3)(4)` calls the lambda that `add(3)` returned, and no name
    /// stands between the two calls.
    ///
    /// **Deliberately not `function("", …)`.** Every `case .function(let name, _)` downstream
    /// keys off the name — the registry, the serializer, the recogniser — and handing them an
    /// empty one would make all of them wrong in the same silent way.
    case call(FormulaAST, [FormulaAST])

    /// An array constant written in the formula: `{1,2,3;4,5,6}`.
    ///
    /// Rows of elements, outer to inner — `{1,2;3,4}` is `[[1, 2], [3, 4]]`. A comma separates
    /// columns and a semicolon separates rows, which is the stored file format's spelling and
    /// not the user's: a workbook saved in a locale that displays `\` for the row separator
    /// still holds `;` in the XML, so this is the only spelling a reader ever sees.
    ///
    /// ## Every row has the same width, and the parser is what guarantees it
    ///
    /// Excel refuses a ragged constant — `{1,2;3}` is a syntax error, not a 2×2 with a hole —
    /// so a value of this case is always rectangular. Nothing downstream re-checks it, and an
    /// array built by hand that breaks the rule will reach a `CellMatrix` initialiser that
    /// rejects it rather than a silent mis-shape.
    ///
    /// ## Only constants go inside
    ///
    /// Numbers, text, booleans and errors. No references, no names, no function calls and no
    /// nested arrays — Excel rejects all of them, and so does the parser. The element type is
    /// `FormulaAST` anyway because there is no smaller type worth defining for four cases, and
    /// because a negative number arrives as one: `{-1,2}` is lexed as a minus and a number,
    /// folded to `.number(-1)` before it lands here.
    ///
    /// ## Why this was missing
    ///
    /// The lexer had no `{`, `}` or `;` token at all, so `{1,2,3}` failed at the first brace
    /// and the gap looked like a decision. It was not one. Found from the side, while writing
    /// a test for something else that wanted a two-row array and could not spell one.
    case arrayConstant([[FormulaAST]])
}

// MARK: - Convenience Builders

extension FormulaAST {

    // MARK: Aggregation

    /// Builds a `SUM(range)` function call.
    public static func sum(_ range: FormulaAST) -> FormulaAST {
        .function("SUM", [range])
    }

    /// Builds an `AVERAGE(range)` function call.
    public static func average(_ range: FormulaAST) -> FormulaAST {
        .function("AVERAGE", [range])
    }

    /// Builds a `COUNT(range)` function call.
    public static func count(_ range: FormulaAST) -> FormulaAST {
        .function("COUNT", [range])
    }

    /// Builds a `MIN(range)` function call.
    public static func min(_ range: FormulaAST) -> FormulaAST {
        .function("MIN", [range])
    }

    /// Builds a `MAX(range)` function call.
    public static func max(_ range: FormulaAST) -> FormulaAST {
        .function("MAX", [range])
    }

    /// Builds a `STDEV(range)` function call.
    public static func stdev(_ range: FormulaAST) -> FormulaAST {
        .function("STDEV", [range])
    }

    /// Builds a `MEDIAN(range)` function call.
    public static func median(_ range: FormulaAST) -> FormulaAST {
        .function("MEDIAN", [range])
    }

    // MARK: Financial

    /// Builds a `PMT(rate, nper, pv)` function call.
    public static func pmt(rate: FormulaAST, nper: FormulaAST, pv: FormulaAST) -> FormulaAST {
        .function("PMT", [rate, nper, pv])
    }

    /// Builds an `IPMT(rate, per, nper, pv)` function call.
    public static func ipmt(rate: FormulaAST, per: FormulaAST,
                             nper: FormulaAST, pv: FormulaAST) -> FormulaAST {
        .function("IPMT", [rate, per, nper, pv])
    }

    /// Builds a `PPMT(rate, per, nper, pv)` function call.
    public static func ppmt(rate: FormulaAST, per: FormulaAST,
                             nper: FormulaAST, pv: FormulaAST) -> FormulaAST {
        .function("PPMT", [rate, per, nper, pv])
    }

    /// Builds an `NPV(rate, values)` function call.
    public static func npv(rate: FormulaAST, values: FormulaAST) -> FormulaAST {
        .function("NPV", [rate, values])
    }

    /// Builds an `IRR(values, guess)` function call.
    public static func irr(values: FormulaAST, guess: FormulaAST = .number(0.1)) -> FormulaAST {
        .function("IRR", [values, guess])
    }

    /// Builds an `FV(rate, nper, pmt)` function call.
    public static func fv(rate: FormulaAST, nper: FormulaAST, pmt: FormulaAST) -> FormulaAST {
        .function("FV", [rate, nper, pmt])
    }

    /// Builds a `PV(rate, nper, pmt)` function call.
    public static func pv(rate: FormulaAST, nper: FormulaAST, pmt: FormulaAST) -> FormulaAST {
        .function("PV", [rate, nper, pmt])
    }

    // MARK: Statistical

    /// Builds a `PERCENTILE(range, k)` function call.
    public static func percentile(_ range: FormulaAST, k: FormulaAST) -> FormulaAST {
        .function("PERCENTILE", [range, k])
    }

    // MARK: Logical

    /// Builds an `IF(test, then, else)` function call.
    public static func `if`(_ test: FormulaAST, then: FormulaAST,
                             `else`: FormulaAST) -> FormulaAST {
        .function("IF", [test, then, `else`])
    }

    // MARK: Lookup

    /// Builds a `VLOOKUP(value, table, col, range_lookup)` function call.
    public static func vlookup(value: FormulaAST, table: FormulaAST,
                                col: FormulaAST, exactMatch: Bool = false) -> FormulaAST {
        .function("VLOOKUP", [value, table, col, .bool(!exactMatch)])
    }
}
