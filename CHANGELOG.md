# Changelog

All notable changes to SwiftExcelCore will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-09-04

### Added

- `FormulaAST.missing` — an argument that is not there.

  `IFERROR(B5/C5-1,)` leaves its second argument out and
  `ADDRESS(row, col, 1, , "Sheet")` leaves out its fourth; the comma still marks the place,
  because position decides which parameter is which. Excel's own binary grammar has a token for
  it, `ptgMissArg`.

  It needs its own case because nothing else says the same thing. `0` and `""` are values a
  formula could have supplied deliberately, so substituting either would report that the sheet
  said something it did not. About 21,500 formulas across 79 measured workbooks need this, and
  they were the last large group SwiftXLSX could not parse.

### Breaking

- Adding an enum case breaks exhaustive `switch` statements over `FormulaAST`. Callers that
  switch without a `default` gain one case to handle. This is the reason for the minor bump
  rather than a patch.


## [0.1.0] - 2026-09-04

The vocabulary a spreadsheet is described in, extracted from SwiftXLSX so that a function
library and a file reader can share it without depending on each other.

### Added

- `CellValue` — what a cell holds: number, text, bool, error, formula with its cached value,
  date, blank, array.
- `CellRef`, `CellRange` — where a cell is, and a rectangle of them, with absolute/relative
  markers preserved.
- `CellAddress`, `SheetReference` — the same, qualified by sheet.
- `ExcelError` — `#DIV/0!`, `#N/A`, `#REF!` and the rest: produced by evaluation, stored by the
  file, and therefore belonging to neither alone.
- `FormulaAST` — what a formula says, independent of how it was written or stored.
- `CellValueProvider` — the protocol by which anything reads cells. This is the seam that lets a
  function library evaluate `VLOOKUP` without knowing what a workbook is.
- `NamedRange`, `NamedRangeTarget`, `NamedRangeCollection`, `NameResolver` — a name bound to a
  target, which both the file and the evaluator have to resolve.

### Notes

Moved unchanged, with their tests — 170 of them. Nothing was improved on the way across, so that
no change hides inside a large diff. Improvements come after, in their own commits.

Foundation only, and intended to stay that way: three packages depend on this one, so a
dependency taken here is taken by all of them.

[Unreleased]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/jpurnell/SwiftExcelCore/releases/tag/v0.2.0
[0.1.0]: https://github.com/jpurnell/SwiftExcelCore/releases/tag/v0.1.0
