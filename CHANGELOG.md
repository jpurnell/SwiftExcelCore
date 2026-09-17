# Changelog

All notable changes to SwiftExcelCore will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.10.0] - 2026-09-17

### Added

- **`NamedRangeTarget.unparsed(String)`** — a refers-to this package could not read, kept
  exactly as the file wrote it.

  **The case that makes a defined name survive a round trip.** SwiftXLSX's writer emits no
  `<definedName>` at all today, and the fix chosen in
  `SwiftExcelFunctions/project/plans/proposals/PROPOSAL_defined_names.md` reconstructs the
  refers-to text *from the target* rather than keeping a copy of the original beside it —
  one fact, one place, nothing that can drift.

  That is only safe if the target can say everything a name can be, and the previous fallback
  could not. A refers-to the resolver failed to parse became `.formula(.text(raw))`, which
  claims the name **is a text constant**. Measured:

  ```
  .text("Expenditures!$D:$D")  →  "Expenditures!$D:$D"   a range becomes a caption
  .text("42")                  →  "42"                   a number becomes a string
  ```

  Neither is a formatting loss; both change what the name *is*. And it is not hypothetical —
  a whole-column name evaluates to its own text today, which is why `SUMIFS(amounts, …)`
  answers zero over 1,058 cells in one corpus workbook.

  `.unparsed` is the honest alternative, and the one target whose round trip is exact by
  construction: reproducing it is the identity function. A reader may then parse only what it
  can prove it reproduces, and everything else is still returned unchanged.

- **`NamedRange.isHidden` and `NamedRange.attributes`** — what a *file* says about a name,
  beyond what an evaluator needs from it.

  Measured across 2,240 workbooks: 1,022 define names, 161,901 names in all, and **74,992 of
  those — 46% — are hidden.** A round trip that kept the target and dropped `hidden` would not
  lose a nicety; it would surface half of every Name Manager, filter ranges and print
  scaffolding and all. On the largest model in the corpus — 47,106 names — that is twenty
  thousand names appearing where none were visible.

  `attributes` holds the rest verbatim (`comment`, `description`, `shortcutKey`, …) rather
  than modelling them: interpreting them is a separate job, and dropping them silently is a
  change to a workbook nobody asked for.

### Changed

- **`NamedRangeTarget` gains a case, so exhaustive switches over it must handle
  `.unparsed`.** The honest answer for an evaluator is `#NAME?` — the name exists in the file
  and this package does not know what it points at, which is what `#NAME?` says.

  Both new `NamedRange` fields default, so every existing initialiser call compiles unchanged.


## [0.9.0] - 2026-09-14

### Changed

- **A whole-row reference keeps its full width instead of being clipped to the data.**
  `clipped(to:)` pulled `$3:$3` back to the last populated column, on the same reasoning that
  governs `$B:$B` — that an unbounded reference asks for the data rather than for the grid.

  That reasoning holds for a column, where keeping the grid means 1,048,576 values. It does
  not hold for a row, which is **16,384 at most** — about a hundred kilobytes.

  And clipping a row was measurably wrong, because everything that counts *positions* depends
  on the width: `INDEX('Raw'!$C$4:$XFD$4, 24)` answered `#REF!` against a fourteen-column
  matrix where Excel reads the blank at column Z, and `COLUMNS($A$1:$XFD$1)` answered `0`
  rather than `16384`. Measured across 46 real workbooks by SwiftExcelFunctions' Excel
  oracle, that was **every disagreement with Excel that remained** after four other fixes.

  A whole column and a whole sheet still pull back, because there the original argument is
  exactly right — and the row bound is what makes the whole-sheet case affordable at all.

  Two tests asserted the old behaviour and are reversed rather than deleted, each recording
  why the decision changed.

## [0.8.0] - 2026-09-10

### Added

- **`CellValueProvider.phonetic(at:)`** — the phonetic reading stored alongside a cell,
  when the file carried one.

  A Japanese workbook records the reading of a name separately from the name: the cell
  says 山田 and an `<rPh>` run says ヤマダ. That is annotation rather than content, so it
  does not belong in `CellValue` — the cell's *value* is unchanged by whether anyone
  wrote down how to say it — and it is asked for by reference instead.

  **A default implementation returns `nil`**, which is what keeps this additive: a
  provider with no phonetic data, or one that does not read a file at all, writes
  nothing and behaves exactly as before. Every existing conformance compiles unchanged;
  the 229 tests that passed before this change still pass without edits.

  Added so that `PHONETIC` can be bound in SwiftExcelFunctions. It pairs with SwiftXLSX
  0.23.2, which stopped concatenating those readings into cell values.

## [0.7.0] - 2026-09-08

### Removed

- **`enum SwiftExcelCore` and its `version` constant.** Scaffold residue, and it had
  started costing something.

  It shadowed the module name, so `SwiftExcelCore.DependencyGraph` did not compile —
  it resolved to a member of the enum, with an error message
  (*"not a member type of enum 'SwiftExcelCore.SwiftExcelCore'"*) that explains
  nothing to anyone who has not already worked it out. The DocC catalogue's own
  ``` # ``SwiftExcelCore`` ``` title was ambiguous for the same reason.

  It was also **wrong**: `version` read `"0.1.0-dev"` while the package was at
  0.6.0. A hardcoded string with nothing keeping it in sync with the tag drifts on
  the first release and then lies quietly. Its only test asserted the literal was
  non-empty, which cannot fail.

  Nothing in the family referenced it, and neither SwiftXLSX nor BusinessMathExcel
  has an equivalent — so it was residue rather than a convention. The module
  documentation it carried already exists, more fully, in the DocC catalogue.

  **Migration:** none expected. If you were reading `SwiftExcelCore.version`, take
  the version from your dependency graph instead, where it is true.


## [0.6.0] - 2026-09-08

### Added

- **`DependencyGraph`**, moved here from SwiftXLSX.

  A dependency graph over cells is a fact *about a set of cells* — which precedes
  which — and holds identically whether they came from an `.xlsx`, a test double, a
  generated model, or a sheet held in memory. It is built from `CellAddress` and
  `FormulaAST`, which live here, so it belongs beside them.

  Its designated initialiser is now `init(cells:provider:)`: an explicit set of
  addresses and a `CellValueProvider`. That is what the old one already read off a
  `Worksheet` — `sheet.name` and `sheet.cells`, a name and a dictionary from
  reference to value — so the type was already written against this abstraction and
  had simply never been given it.

  **The cell set is supplied rather than discovered.** `CellValueProvider` answers
  "what is at this address?" and cannot be asked "which addresses do you have?", and
  the graph needs the opposite: it builds its scope first, because an edge can only
  be kept once both ends are known to belong. Deriving the set from a range would
  mean probing every address in the rectangle — `rows × columns` however sparse the
  sheet, and real models are sparse and wide.

  `sheetScope` and `including` are retained as defaulted parameters, because
  SwiftXLSX's `init(sheet:including:)` is built on both.

  Nothing else changed: the traversal, Kahn's sort, the cycle detection and the
  whole-column range intersection are the same code.

  SwiftXLSX keeps `init(workbook:)`, `init(sheet:including:)` and
  `init(workbook:including:)` as an extension over this, so its callers are
  unaffected.


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

[Unreleased]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.10.0...HEAD
[0.10.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/jpurnell/SwiftExcelCore/releases/tag/v0.2.0
[0.1.0]: https://github.com/jpurnell/SwiftExcelCore/releases/tag/v0.1.0
