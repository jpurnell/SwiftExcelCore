/// A directed acyclic graph of cell dependencies built from formula ASTs.
///
/// Use `DependencyGraph` to determine the correct evaluation order for cells,
/// detect circular references, and query dependency relationships.
///
/// ## Why this lives here
///
/// A dependency graph over cells is a fact *about a set of cells* — which precedes
/// which — and holds identically whether they came from an `.xlsx`, a test double, a
/// generated model, or a sheet held in memory. It is built from ``CellAddress`` and
/// ``FormulaAST``, which live here, so it belongs beside them rather than in the
/// package that happens to read files.
///
/// ```swift
/// struct Sheet: CellValueProvider {
///     var cells: [CellAddress: CellValue]
///     func value(at ref: CellRef) -> CellValue? { value(at: ref, inSheet: "Model") }
///     func value(at ref: CellRef, inSheet: String) -> CellValue? {
///         cells[CellAddress(sheet: inSheet, cell: ref)]
///     }
///     func lastPopulatedCell() -> CellRef? { nil }
///     func lastPopulatedCell(inSheet: String) -> CellRef? { nil }
///     func values(in range: CellRange) -> [CellValue] { [] }
///     func values(in range: CellRange, inSheet: String) -> [CellValue] { [] }
/// }
///
/// let sheet = Sheet(cells: [
///     CellAddress(sheet: "Model", ref: "A1"): .number(10),
///     CellAddress(sheet: "Model", ref: "B1"):
///         .formula(.multiply(.cellRef(CellRef("A1")), .number(2)), cached: nil),
/// ])
///
/// let graph = DependencyGraph(cells: Array(sheet.cells.keys), provider: sheet)
/// print(graph.evaluationOrder.map(\.cell.reference))   // ["A1", "B1"]
/// ```
///
/// SwiftXLSX layers `init(workbook:)`, `init(sheet:including:)` and
/// `init(workbook:including:)` over this, for callers who have a file.
public struct DependencyGraph: Sendable {

    /// Errors during graph construction.
    public enum GraphError: Error, Equatable, Sendable {
        /// A circular reference was detected involving the given cells.
        case circularReference([CellAddress]) // LIVE: public API for consumers
    }

    // MARK: - Internal Storage

    /// Maps each cell to the set of cells it directly depends on (precedents).
    private let precedentMap: [CellAddress: [CellAddress]]

    /// Maps each cell to the set of cells that directly depend on it (dependents).
    private let dependentMap: [CellAddress: [CellAddress]]

    /// Every cell in the graph.
    ///
    /// Worth having separately from ``evaluationOrder``, which is empty when the
    /// graph has a cycle — so with a cycle present there would otherwise be no way
    /// to enumerate membership at all. That matters most for a scoped graph, where
    /// knowing what the scope kept is the first thing a caller asks.
    public let allCells: Set<CellAddress>

    /// Cells in topological order, computed during init. Empty if cycles exist.
    private let sortedCells: [CellAddress]

    /// Detected cycles, if any.
    private let detectedCycles: [[CellAddress]]

    // MARK: - Init

    /// Builds the dependency graph over an explicit set of cells.
    ///
    /// ## Why the cell set is given rather than discovered
    ///
    /// ``CellValueProvider`` answers *"what is at this address?"* and cannot be asked
    /// *"which addresses do you have?"*. The graph needs the opposite: it builds its
    /// scope first, because an edge can only be kept once both ends are known to
    /// belong. So the caller supplies the set.
    ///
    /// That is not a performance accommodation. Deriving a cell set from a range
    /// through this protocol means probing every address in the rectangle, which is
    /// `rows × columns` however sparse the sheet — and real models are sparse and
    /// wide. A caller supplying the set has necessarily thought about where it came
    /// from.
    ///
    /// ## Scope
    ///
    /// ``CellAddress`` carries its sheet, so passing addresses from several sheets
    /// builds a cross-sheet graph and passing one sheet's builds a narrow one. There
    /// is no separate scoping concept: the caller expresses scope by choosing what to
    /// pass.
    ///
    /// - Parameters:
    ///   - cells: Every address in scope.
    ///   - provider: Answers the value at each address.
    ///   - sheetScope: The sheet names a reference may point at, or `nil` to allow
    ///     any. Non-`nil` drops a reference onto another sheet along with its edge.
    ///   - including: Whether a cell belongs, given its value. `nil` keeps every cell
    ///     — which also keeps *referenced* cells that hold nothing, because an
    ///     evaluator still has to visit one to learn it is zero.
    public init(
        cells: [CellAddress],
        provider: any CellValueProvider,
        sheetScope: Set<String>? = nil,
        including: ((CellValue) -> Bool)? = nil
    ) {
        var precedents: [CellAddress: [CellAddress]] = [:]
        var dependents: [CellAddress: [CellAddress]] = [:]
        var graphCells: Set<CellAddress> = []

        func value(at address: CellAddress) -> CellValue? {
            provider.value(at: address.cell, inSheet: address.sheet)
        }

        // Which addresses are in scope at all. Built first, because an edge can
        // only be kept once both ends are known to belong.
        var inScope: Set<CellAddress> = []
        for address in cells {
            guard let cellValue = value(at: address) else { continue }
            guard including?(cellValue) ?? true else { continue }
            inScope.insert(address)
        }

        for address in cells {
            guard inScope.contains(address) else { continue }
            graphCells.insert(address)

            guard let cellValue = value(at: address),
                  case .formula(let ast, _) = cellValue else { continue }
            let refs = DependencyGraph.extractReferences(
                from: ast, inSheet: address.sheet, populated: inScope)

            // Deduplicate while preserving order.
            var seen = Set<CellAddress>()
            var uniqueRefs: [CellAddress] = []
            for ref in refs where seen.insert(ref).inserted {
                // A reference off the scoped sheets is out of scope whether or not a
                // content filter was given: the caller asked for a graph over these
                // sheets, and another sheet's cell is not on them.
                if let sheetScope, !sheetScope.contains(ref.sheet) { continue }

                // With a filter, a reference to an excluded cell is dropped with its
                // edge. Without one, every referenced address becomes a node —
                // including cells holding nothing — which is what an evaluator needs.
                if including != nil && !inScope.contains(ref) { continue }

                uniqueRefs.append(ref)
            }

            precedents[address] = uniqueRefs
            for ref in uniqueRefs {
                graphCells.insert(ref)
                dependents[ref, default: []].append(address)
            }
        }

        self.precedentMap = precedents
        self.dependentMap = dependents
        self.allCells = graphCells

        let (sorted, cycles) = DependencyGraph.topologicalSort(
            cells: graphCells,
            precedents: precedents,
            dependents: dependents
        )
        self.sortedCells = sorted
        self.detectedCycles = cycles
    }

    // MARK: - Public API

    /// All cells in topological order (evaluate in this order).
    ///
    /// Cells with no dependencies appear first, followed by cells that
    /// depend only on already-listed cells. If cycles exist, only the
    /// acyclic portion is included.
    public var evaluationOrder: [CellAddress] {
        sortedCells
    }

    /// Cells with no formula -- the inputs to the model.
    ///
    /// A cell is an input if it has no precedents (i.e., it does not contain
    /// a formula referencing other cells).
    public var inputs: [CellAddress] {
        allCells
            .filter { (precedentMap[$0] ?? []).isEmpty }
            .sorted { $0.sortKey < $1.sortKey }
    }

    /// Cells with no dependents -- the outputs of the model.
    ///
    /// A cell is an output if no other cell's formula references it.
    public var outputs: [CellAddress] {
        allCells
            .filter { (dependentMap[$0] ?? []).isEmpty }
            .sorted { $0.sortKey < $1.sortKey }
    }

    /// Cells that directly depend on the given cell.
    ///
    /// - Parameter cell: The cell to query.
    /// - Returns: Cells whose formulas reference this cell.
    public func dependents(of cell: CellAddress) -> [CellAddress] {
        dependentMap[cell] ?? []
    }

    /// Cells that the given cell directly references in its formula.
    ///
    /// - Parameter cell: The cell to query.
    /// - Returns: Cells referenced by this cell's formula.
    public func precedents(of cell: CellAddress) -> [CellAddress] {
        precedentMap[cell] ?? []
    }

    /// All cells downstream of the given cell (transitive dependents).
    ///
    /// Uses breadth-first traversal to find all cells that would need
    /// recalculation if the given cell's value changed.
    ///
    /// - Parameter cell: The starting cell.
    /// - Returns: All transitively dependent cells.
    public func allDependents(of cell: CellAddress) -> Set<CellAddress> {
        var result = Set<CellAddress>()
        var queue = dependentMap[cell] ?? []

        // Guard: iterative BFS, no recursion needed
        while let current = queue.first {
            queue.removeFirst()
            guard result.insert(current).inserted else { continue }
            queue.append(contentsOf: dependentMap[current] ?? [])
        }

        return result
    }

    /// True if the graph has no cycles.
    public var isAcyclic: Bool {
        detectedCycles.isEmpty
    }

    /// If cycles exist, returns the cells involved in each cycle.
    public var cycles: [[CellAddress]] {
        detectedCycles
    }

    // MARK: - Reference Extraction

    /// Extracts all cell address references from a formula AST.
    ///
    /// Recursively walks the AST and collects every cell reference,
    /// including those inside ranges and cross-sheet references.
    ///
    /// - Parameters:
    ///   - ast: The formula AST to walk.
    ///   - inSheet: The name of the sheet containing the formula (for unqualified refs).
    /// - Returns: All cell addresses referenced by the formula.
    /// A reference with its `$` markers dropped.
    ///
    /// A marker says how a formula *fills* when copied, not which cell it means:
    /// `$C12`, `C$12` and `C12` are one cell. ``CellRef`` hashes the markers, so
    /// carrying them into the graph splits a cell into as many nodes as the forms
    /// used to reach it — a phantom `$B$3` beside the real `B3`, with the edges
    /// divided between them.
    ///
    /// That is not a small error on real models. A mixed reference is how a rule
    /// fills across a row while holding one operand still, so the edges lost are
    /// exactly the ones tying every period back to its assumptions.
    ///
    /// - Parameter reference: The reference as written.
    /// - Returns: The same cell, unmarked.
    private static func unmarked(_ reference: CellRef) -> CellRef {
        CellRef(column: reference.column, row: reference.row)
    }

    /// The cells a range depends on.
    ///
    /// Small ranges enumerate exactly, empty cells included: `A1:A5` names five
    /// cells whether or not anything is in them, and a referenced empty cell is
    /// still a cell an evaluator must visit to learn it is zero.
    ///
    /// **A whole-column range is a different statement.** `$B:$G` is not a request
    /// for 6,291,456 cells; it is a request for whatever is in those columns, and
    /// the corpus writes it 87,773 times in `VLOOKUP` alone. Enumerating it would
    /// produce hundreds of billions of addresses, so above ``exactEnumerationLimit``
    /// the range is intersected with the cells that actually exist.
    ///
    /// The cutoff is a size at which no one is naming cells individually any more.
    /// Below it the behaviour is exactly what it has always been.
    private static func addresses(
        in range: CellRange,
        sheet: String,
        populated: Set<CellAddress>
    ) -> [CellAddress] {
        let size = range.rowCount * range.columnCount
        if size <= exactEnumerationLimit {
            return range.cells.map { CellAddress(sheet: sheet, cell: unmarked($0)) }
        }

        let low = range.start
        let high = range.end
        return populated
            .filter { address in
                address.sheet == sheet
                    && address.cell.column >= low.column && address.cell.column <= high.column
                    && address.cell.row >= low.row && address.cell.row <= high.row
            }
            .map { CellAddress(sheet: $0.sheet, cell: unmarked($0.cell)) }
            .sorted { ($0.cell.row, $0.cell.column) < ($1.cell.row, $1.cell.column) }
    }

    /// The largest range enumerated cell by cell, empty cells included.
    ///
    /// 4,096 is four columns of a thousand rows — larger than any range a person
    /// writes out deliberately, and far smaller than a single whole column.
    static let exactEnumerationLimit = 4_096

    private static func extractReferences(
        from ast: FormulaAST,
        inSheet: String,
        populated: Set<CellAddress>
    ) -> [CellAddress] {
        // Guard: base cases return immediately, recursive cases reduce AST depth
        switch ast {
        case .cellRef(let ref):
            return [CellAddress(sheet: inSheet, cell: unmarked(ref))]

        case .cellRange(let range):
            return addresses(in: range, sheet: inSheet, populated: populated)

        case .sheetRef(let sheetRef):
            return addresses(in: sheetRef.range, sheet: sheetRef.sheetName, populated: populated)

        case .namedRange:
            // Named range resolution requires a NameResolver; skip for now
            return []

        case .number, .text, .bool, .error, .missing:
            // An argument that is not there reads nothing.
            return []

        case .add(let l, let r),
             .subtract(let l, let r),
             .multiply(let l, let r),
             .divide(let l, let r),
             .power(let l, let r),
             .concatenate(let l, let r),
             .equal(let l, let r),
             .notEqual(let l, let r),
             .greaterThan(let l, let r),
             .lessThan(let l, let r),
             .greaterOrEqual(let l, let r),
             .lessOrEqual(let l, let r):
            return extractReferences(from: l, inSheet: inSheet, populated: populated)
                 + extractReferences(from: r, inSheet: inSheet, populated: populated)

        case .negate(let expr):
            return extractReferences(from: expr, inSheet: inSheet, populated: populated)

        case .function(_, let args):
            return args.flatMap {
                extractReferences(from: $0, inSheet: inSheet, populated: populated)
            }
        case .call(let callee, let args):
            // The callee is an expression and may hold references of its own — a lambda's
            // body can read the sheet. Walking only the arguments would miss them.
            return ([callee] + args).flatMap {
                extractReferences(from: $0, inSheet: inSheet, populated: populated)
            }
        }
    }

    // MARK: - Topological Sort

    /// Performs Kahn's algorithm for topological sorting.
    ///
    /// - Parameters:
    ///   - cells: All cells in the graph.
    ///   - precedents: Map from each cell to its direct precedents.
    ///   - dependents: Map from each cell to its direct dependents.
    /// - Returns: A tuple of (sorted cells, detected cycles).
    private static func topologicalSort(
        cells: Set<CellAddress>,
        precedents: [CellAddress: [CellAddress]],
        dependents: [CellAddress: [CellAddress]]
    ) -> ([CellAddress], [[CellAddress]]) {
        guard !cells.isEmpty else { return ([], []) }

        // Compute in-degree for each cell
        var inDegree: [CellAddress: Int] = [:]
        for cell in cells {
            inDegree[cell] = (precedents[cell] ?? []).count
        }

        // Start with cells that have in-degree 0 (no dependencies)
        var queue = cells
            .filter { inDegree[$0] == 0 }
            .sorted { $0.sortKey < $1.sortKey }
        var result: [CellAddress] = []

        while let current = queue.first {
            queue.removeFirst()
            result.append(current)

            // For each dependent, reduce its in-degree
            for dep in dependents[current] ?? [] {
                guard var degree = inDegree[dep] else { continue }
                degree -= 1
                inDegree[dep] = degree
                if degree == 0 {
                    // Insert in sorted order for deterministic output
                    let insertIdx = queue.firstIndex { $0.sortKey > dep.sortKey } ?? queue.endIndex
                    queue.insert(dep, at: insertIdx)
                }
            }
        }

        // If not all cells were processed, there are cycles
        var detectedCycles: [[CellAddress]] = []
        if result.count < cells.count {
            let remaining = cells.subtracting(Set(result))
            detectedCycles = findCycles(in: remaining, precedents: precedents)
        }

        return (result, detectedCycles)
    }

    // MARK: - Cycle Detection

    /// Finds cycles among the remaining (unprocessed) nodes using DFS.
    ///
    /// - Parameters:
    ///   - nodes: The set of nodes known to be part of cycles.
    ///   - precedents: The precedent map.
    /// - Returns: An array of cycle paths.
    private static func findCycles(
        in nodes: Set<CellAddress>,
        precedents: [CellAddress: [CellAddress]]
    ) -> [[CellAddress]] {
        var visited = Set<CellAddress>()
        var cycles: [[CellAddress]] = []

        for node in nodes.sorted(by: { $0.sortKey < $1.sortKey }) {
            guard !visited.contains(node) else { continue }

            // Follow precedent chain within remaining nodes to find cycle
            var path: [CellAddress] = []
            var current = node
            var pathSet = Set<CellAddress>()

            // Guard: each iteration either adds to path or exits
            while !pathSet.contains(current) {
                pathSet.insert(current)
                path.append(current)
                visited.insert(current)

                // Follow a precedent that is also in the remaining set
                let nextCandidates = (precedents[current] ?? []).filter { nodes.contains($0) }
                guard let next = nextCandidates.first else { break }
                current = next
            }

            // If we found a cycle, extract the cycle portion
            if let cycleStart = path.firstIndex(of: current) {
                let cycle = Array(path[cycleStart...])
                if !cycle.isEmpty {
                    cycles.append(cycle)
                }
            }
        }

        return cycles
    }
}

// MARK: - CellAddress Sort Key

extension CellAddress {
    /// A deterministic sort key for consistent ordering: sheet name, then column, then row.
    var sortKey: String {
        let colStr = String(cell.column)
        let rowStr = String(cell.row)
        let col = String(repeating: "0", count: max(0, 6 - colStr.count)) + colStr
        let row = String(repeating: "0", count: max(0, 9 - rowStr.count)) + rowStr
        return "\(sheet)!\(col)\(row)"
    }
}
