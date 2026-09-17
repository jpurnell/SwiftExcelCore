/// Standard Excel error values.
public enum ExcelError: String, Equatable, Hashable, Sendable, CustomStringConvertible {
    case value = "#VALUE!" // LIVE: public API for consumers
    case ref = "#REF!" // LIVE: public API for consumers
    case div0 = "#DIV/0!" // LIVE: public API for consumers
    case name = "#NAME?"
    case null = "#NULL!" // LIVE: public API for consumers
    case num = "#NUM!" // LIVE: public API for consumers
    case na = "#N/A" // LIVE: public API for consumers
    /// A formula that cannot produce a value — most often a `LAMBDA` that was never called.
    ///
    /// `=LAMBDA(x, x+1)` typed into a cell is a function sitting where a value belongs, and
    /// Excel answers `#CALC!` rather than showing anything. Newer than the other six, and
    /// added here because ``CellValue/lambda(parameters:body:captured:)`` made the situation
    /// representable: without the error a lambda in a cell had to become `#VALUE!`, which is
    /// a different thing and says the wrong one.
    case calc = "#CALC!" // LIVE: public API for consumers

    /// The raw error string, e.g. `#VALUE!`.
    public var description: String { rawValue }
}
