/// A cross-sheet cell or range reference, e.g. `'Sheet1'!A1:B10`.
public struct SheetReference: Equatable, Hashable, Sendable {
    /// The name of the referenced worksheet.
    public let sheetName: String
    /// The cell range within the referenced sheet.
    public let range: CellRange

    /// Creates a sheet reference to a cell range.
    public init(sheet: String, range: CellRange) {
        self.sheetName = sheet
        self.range = range
    }

    /// Creates a sheet reference to a single cell.
    public init(sheet: String, cell: CellRef) {
        self.sheetName = sheet
        self.range = CellRange(from: cell, to: cell)
    }

    /// The two sheets this reference spans, when it spans any.
    ///
    /// **`'Q1:Q4'!B7` is Excel's 3-D reference**, and the span arrives here already intact: a
    /// parser reading `'first:last'!A1` puts `first:last` into ``sheetName`` whole. Excel
    /// forbids `:` in a sheet name — one of the seven characters a sheet may not contain — so
    /// splitting on it identifies a span rather than guessing at someone's naming.
    ///
    /// `nil` where there is no span, including for the malformed spellings a file should not
    /// contain: an empty end, or more than two names. Half a span is not half an answer, and
    /// reading one as a single sheet is exactly the failure this exists to end — a corpus run
    /// answered 28 where Excel answered 47, because the span terms silently contributed
    /// nothing while the single-sheet terms beside them were fine.
    public var span: (first: String, last: String)? {
        let parts = sheetName.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    /// The sheets this reference reads, in the workbook's own order.
    ///
    /// A span covers every sheet **positionally between its ends**, inclusive — which is why
    /// the order has to come from the workbook and cannot be worked out from the names. A
    /// reference that is not a span is its own single sheet.
    ///
    /// An end that names no sheet spans nothing, which matches what a provider already does
    /// with an absent sheet: reads as empty rather than failing. Quietly dropping to one end
    /// would recreate the bug this replaces.
    ///
    /// - Parameter provider: The workbook, for its sheet order.
    /// - Returns: The sheets to read, in order.
    public func sheets(in provider: some CellValueProvider) -> [String] {
        guard let span else { return [sheetName] }
        let order = provider.sheetNames()
        guard let one = order.firstIndex(of: span.first),
              let other = order.firstIndex(of: span.last) else { return [] }
        // Written backwards is still a span: Excel reads the pair, not a direction.
        return Array(order[min(one, other)...max(one, other)])
    }

    /// The formatted reference string with quoted sheet name.
    public var reference: String {
        let escaped = sheetName.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'!\(range.reference)"
    }
}
