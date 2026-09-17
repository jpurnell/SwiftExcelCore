// MARK: - NameScope

/// The scope of a named range: workbook-wide or sheet-specific.
public enum NameScope: Sendable, Equatable, Hashable {
    case workbook
    case sheet(String)
}

// MARK: - NamedRangeTarget

/// What a named range resolves to.
///
/// ## One representation, and a case that admits ignorance
///
/// A name is held exactly once: this target *is* the name's meaning, and nothing keeps a
/// competing copy of the refers-to text beside it. A writer reproduces the text from here, so
/// there is no second version to fall out of step with the first.
///
/// That only works if the target can say everything a name can be — including "I could not
/// read this one", which is what ``unparsed(_:)`` is for. Without it a reader has to
/// misrepresent what it failed to parse, and the misrepresentation is not harmless: the
/// previous fallback was `.formula(.text(raw))`, which claims the name **is a text constant**.
/// Writing that back turns `Expenditures!$D:$D` into the string `"Expenditures!$D:$D"` and the
/// number `42` into the string `"42"`, and evaluating it hands a formula a caption where it
/// expected a range.
public enum NamedRangeTarget: Sendable, Equatable, Hashable {
    case cell(CellRef) // LIVE: public API for consumers
    case range(CellRange) // LIVE: public API for consumers
    case sheetCell(SheetReference) // LIVE: public API for consumers
    case sheetRange(SheetReference) // LIVE: public API for consumers
    case formula(FormulaAST) // LIVE: public API for consumers

    /// A refers-to this package could not read, kept exactly as the file wrote it.
    ///
    /// **Not a failure state — a true statement**, and the one target whose round trip is
    /// exact by construction, because reproducing it is the identity function. A reader that
    /// can say this is free to parse only what it can reproduce, which is what makes
    /// reconstructing the text from the target safe at all.
    ///
    /// An evaluator should answer `#NAME?` for one of these: the name exists in the file and
    /// this package does not know what it points at, which is precisely what `#NAME?` says.
    case unparsed(String) // LIVE: public API for consumers
}

// MARK: - NamedRange

/// An Excel named range binding a name to a cell, range, or formula.
///
/// Carries what a *file* says about a name, not only what an evaluator needs from it, so that
/// a workbook read and written back keeps its name table intact. Measured across 2,240
/// workbooks: 1,022 of them define names, 161,901 names in all, and **74,992 of those — 46%
/// — are hidden.** A round trip that kept the target and dropped ``isHidden`` would not lose
/// a nicety; it would surface half of every Name Manager, filter ranges and print scaffolding
/// and all.
public struct NamedRange: Sendable, Equatable, Hashable {
    /// The name of this named range.
    public let name: String
    /// The target this name resolves to.
    public let reference: NamedRangeTarget
    /// Whether this name is workbook-scoped or sheet-scoped.
    public let scope: NameScope

    /// Whether Excel hides this name from the Name Manager.
    ///
    /// Filter ranges, print views and the `.wvu.` scaffolding Excel writes for custom views
    /// are all hidden, and they are the *majority* of names in a real corpus.
    public let isHidden: Bool

    /// Attributes this package does not interpret, kept so a writer can put them back.
    ///
    /// `comment`, `description`, `shortcutKey`, `customMenu`, `function`, `vbProcedure` and
    /// the rest. Held verbatim rather than modelled: interpreting them is a separate job and
    /// dropping them silently is a change to a workbook nobody asked for.
    public let attributes: [String: String]

    /// Creates a named range with the given name, target, and scope.
    ///
    /// - Parameters:
    ///   - name: The name as the file writes it.
    ///   - reference: What the name points at.
    ///   - scope: Workbook-wide, or one sheet.
    ///   - isHidden: Whether Excel hides it from the Name Manager.
    ///   - attributes: Attributes this package does not interpret.
    public init(
        name: String,
        reference: NamedRangeTarget,
        scope: NameScope = .workbook,
        isHidden: Bool = false,
        attributes: [String: String] = [:]
    ) {
        self.name = name
        self.reference = reference
        self.scope = scope
        self.isHidden = isHidden
        self.attributes = attributes
    }
}

// MARK: - NameResolver Protocol

/// Resolves named range identifiers to their targets.
public protocol NameResolver: Sendable {
    /// Resolves a name, optionally within a specific sheet context.
    func resolve(_ name: String, inSheet: String?) -> NamedRangeTarget?
}

// MARK: - NamedRangeCollection

/// A collection of named ranges with case-insensitive resolution.
public struct NamedRangeCollection: Sendable {
    private var ranges: [NamedRange] = []

    /// Creates an empty collection.
    public init() {}

    /// Creates a collection from an array of named ranges.
    public init(_ ranges: [NamedRange]) {
        self.ranges = ranges
    }

    /// Adds a named range to the collection.
    public mutating func add(_ range: NamedRange) {
        ranges.append(range)
    }

    /// Resolves a name with sheet-scope-takes-precedence semantics.
    public func resolve(_ name: String, inSheet: String? = nil) -> NamedRangeTarget? {
        let lowercasedName = name.lowercased()

        var workbookMatch: NamedRangeTarget?
        var sheetMatch: NamedRangeTarget?

        for range in ranges {
            guard range.name.lowercased() == lowercasedName else { continue }

            switch range.scope {
            case .workbook:
                if workbookMatch == nil {
                    workbookMatch = range.reference
                }
            case .sheet(let sheetName):
                if let inSheet, sheetName == inSheet, sheetMatch == nil {
                    sheetMatch = range.reference
                }
            }
        }

        return sheetMatch ?? workbookMatch
    }

    /// All named ranges in the collection.
    public var all: [NamedRange] { ranges }

    /// The number of named ranges.
    public var count: Int { ranges.count }
}

// MARK: - NamedRangeCollection + NameResolver

extension NamedRangeCollection: NameResolver {}
