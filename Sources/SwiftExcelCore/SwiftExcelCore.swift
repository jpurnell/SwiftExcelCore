/// The vocabulary a spreadsheet is described in.
///
/// What a cell holds, where it sits, what a formula says, and what went wrong.
/// Nothing else, and deliberately so: three packages depend on this one, so every
/// change here is a three-repository release.
///
/// ## Why this package exists
///
/// A function library that evaluates `VLOOKUP` and a file reader that parses
/// `=VLOOKUP(...)` both need `CellRef` and `CellValue`. Neither needs the other.
/// Without a shared vocabulary one would have to depend on the other, and the
/// dependency would run the wrong way — a library of mathematics importing a ZIP
/// archive reader.
///
/// ## What is not here
///
/// Parsing and file storage are SwiftXLSX's. Function implementations and
/// evaluation are SwiftExcelFunctions'. Styling is presentation and will have its
/// own package. Anything opinionated is somebody else's, because this package is
/// only useful while it holds still.
public enum SwiftExcelCore {

    /// The package version, as a human-readable string.
    public static let version = "0.1.0-dev"
}
