# Changelog

All notable changes to SwiftExcelCore will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-09-05

### Added

- **`CellMatrix.spilled(toRows:columns:)`** — the rectangle a result becomes when
  one formula fills a span.

  A formula entered over a range evaluates once and its result fills the whole
  rectangle, whose shape need not match. Excel reconciles the two by broadcasting a
  dimension of 1, padding what the result cannot reach with `#N/A`, and truncating
  what does not fit. All three are here, as a pure function of the two shapes.

  A blank *inside* the result stays blank; only cells beyond its reach become
  `#N/A`. That distinction is what makes a spilled rectangle readable — `#N/A`
  means "the formula had nothing for this cell", which is not the same as "the
  formula produced an empty one".

## [0.4.0] - 2026-09-05

### Changed

- **`matrix(in:)` no longer refuses large ranges, and no longer returns an optional.**

  0.3.0 bounded the read with a constant, `CellMatrix.maximumCells`, chosen by
  reasoning about the grid's dimensions. That was a threshold standing in for a
  principle, and it answered `#VALUE!` to formulas Excel answers perfectly well.

  The principle is the one SwiftXLSX's dependency graph already states about the
  same notation: `$B:$B` is not a request for 1,048,576 cells, it is a request for
  whatever is in column B. So a range that runs to the grid's last row or column is
  clipped to where the sheet's data actually ends. Nothing can lie beyond the last
  row, so a range reaching it was never describing a chosen bottom edge.

  The test is structural, not a size: `CellRange.extendsToLastRow` and
  `extendsToLastColumn`. A range written out by hand is never touched however
  sparse the sheet, because `COUNTBLANK(A1:B3)` is six on an empty sheet and a clip
  answering zero would be worse than the allocation it saved. The origin never
  moves either, so `INDEX($A:$A, 3)` still means the third row.

### Added

- `CellValueProvider.lastPopulatedCell()` and `lastPopulatedCell(inSheet:)`.

  A provider is the only party that knows where its data stops, so it is the only
  one that can make a whole-column reference affordable. `nil` means the sheet
  holds *nothing*; a provider that does not know its bounds says so by naming
  `CellRef.lastOnSheet`, which clips nothing. Both states are real and lead to
  opposite behaviour, so neither is inferred from the other.

- `CellRange.clipped(to:)`, `CellRange.extendsToLastRow`,
  `CellRange.extendsToLastColumn`, `CellRef.lastOnSheet`.

### Removed

- `CellMatrix.maximumCells`. There is nothing left to bound.

### Breaking

- `CellValueProvider` gains two requirements. Conformances must say where their
  data stops — a dictionary-backed provider answers from its keys in three lines.
- `matrix(in:)` returns `CellMatrix` rather than `CellMatrix?`. Callers handling
  the refusal case can delete it.

## [0.3.0] - 2026-09-05

### Added

- `CellMatrix` — a rectangle of cell values that carries its own `rows` and `columns`.

  Its initializer fails unless the elements fill the rectangle exactly, so a matrix that
  disagrees with itself cannot be built and every accessor may trust the dimensions.
  Row-major throughout, matching `CellRange.cells`, so a range and its values agree by
  construction rather than by convention.

- `CellValueProvider.matrix(in:)` and `matrix(in:inSheet:)`, with default implementations
  derived from `value(at:)`.

  Every conforming type already has `value(at:)`, so each gets a correct shaped read
  without writing one. Empty cells arrive as `.blank` in their own position rather than
  closing the gap.

- `CellMatrix.maximumCells` (262,144) — the bound above which a range is refused.

  Keeping blanks means a sparse range now costs what its rectangle costs rather than what
  its contents do. A whole column is 1,048,576 cells and a whole row 16,384: the first has
  to be refused and the second must not be, which is what puts the bound between them.
  `matrix(in:)` returns `nil` rather than allocating, so refusal is representable.

### Changed

- `CellValue.array` now holds a `CellMatrix` instead of a `[CellValue]`.

### Deprecated

- `CellValueProvider.values(in:)` and `values(in:inSheet:)`. Behaviour is unchanged —
  they still skip blanks — but a flat read cannot preserve position, which is what
  callers actually needed.

### Breaking

- `CellValue.array`'s payload type changed. Pattern matches that bind the payload
  (`case .array(let items)`) need updating; bare `case .array:` matches are unaffected.

  The reason for the change rather than an additive one: consumers had been re-deriving
  the shape a range lost, and two derived it wrongly. `INDEX(A1:A4, 3)` over a range whose
  second cell was empty returned the fourth value, because the blank was deleted before
  INDEX could count past it. `VLOOKUP` guessed its table's width by testing which divisors
  came out even, and returned `#N/A` for a four-column table asked for its third column.
  Both were measured against the build, not predicted.

  Keeping a flat `.array` beside a shaped one would have left every future consumer to
  handle both, so the lossy representation is gone rather than deprecated.

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
[0.5.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/jpurnell/SwiftExcelCore/releases/tag/v0.2.0
[0.1.0]: https://github.com/jpurnell/SwiftExcelCore/releases/tag/v0.1.0
