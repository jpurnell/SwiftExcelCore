import Foundation

/// A field on a pivot table's row or column axis.
///
/// ## Why this is not a `String`
///
/// A pivot table definition lists its axes by **index** — `<field x="4"/>` — and one index is
/// not an index at all. **`-2` is the "values" pseudo-field**: it marks the position where the
/// *data field names* are rendered, which is how a pivot with four data fields stacks them
/// down the rows instead of spreading them across the columns.
///
/// Measured: 15 of the 50 pivots in `Dot Com YTD Performance Report 6 20.xlsx` carry it, and
/// `pivotTable7` renders its row axis as
///
/// ```
/// Values | Scenario | Region
///  B1    | CY       | GBR
///        |          | WNE
///  HSI   | CY       | GBR
/// ```
///
/// where column `C` holds the data field captions rather than any field's items.
///
/// Excel writes the word **`Values`** into that header cell, and a list of `String` would have
/// to store that word — at which point a workbook with a real field named `Values` becomes
/// indistinguishable from this one. A case cannot collide with a name, so this is a case.
public enum PivotAxisField: Equatable, Hashable, Sendable {

    /// An ordinary field, named as the pivot cache names it.
    case field(String)

    /// The `-2` pseudo-field: the position where the data field names are rendered.
    case dataFieldNames

    /// Whether this is the field a formula means when it names `name`.
    ///
    /// **Case-insensitive, and never trimmed.** The corpus forces both: its cache spells a
    /// field `week ending` while every formula writes `"Week Ending"`, and three data field
    /// captions in the same workbook are written with a **leading space** (`" B1"`), which a
    /// trim would collapse onto names nobody asked for.
    ///
    /// The pseudo-field answers to no name at all — it is selected by the `data_field`
    /// argument, not by a field/item pair.
    ///
    /// - Parameter name: The name a formula wrote.
    /// - Returns: `true` where this field is the one meant.
    public func matches(_ name: String) -> Bool {
        guard case .field(let own) = self else { return false }
        return own.lowercased() == name.lowercased()
    }
}
