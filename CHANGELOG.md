# Changelog

All notable changes to SwiftExcelCore will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.15.0] - 2026-09-20

### Added

- **A reference can span sheets.** `'Q1:Q4'!B7` is Excel's 3-D reference, and this package
  could not express one — `SheetReference` held a single `sheetName`, so a span matched no
  sheet and read as empty.

  The span was arriving intact all along: a parser reading `'first:last'!A1` puts
  `first:last` into `sheetName` whole. `span` reads the two ends back out. Excel forbids `:`
  in a sheet name — one of the seven characters a sheet may not contain — so splitting on it
  identifies a span rather than guessing at someone's naming. A malformed spelling is not
  half a span: an empty end, or more than two names, reads as none.

- **`CellValueProvider.sheetNames()`**, because expanding a span needs the workbook's order.
  A span covers every sheet *positionally* between its ends, and no amount of reading the
  names will say what sits there.

  **Additive**, in the way `phonetic(at:)` already was: the default returns none, so every
  existing conformance compiles and behaves exactly as before, and a provider that does not
  model a workbook — a test double, a single sheet — reads a 3-D reference as empty rather
  than failing. It has no order to give, and empty is the honest answer.

  `SheetReference.sheets(in:)` expands a reference against a provider. An end that names no
  sheet spans nothing, matching what a provider already does with an absent sheet. Quietly
  dropping to one end would recreate the bug this replaces.

### Why now

A corpus run over 300 real workbooks found **9,958 cells** in one of them summing across
spans of sheets — `SUM('8887997613:8887997618'!DL62)`, a sheet per account. The package
answered **28** where Excel answered **47**.

The failure was silent rather than loud, which is why it had survived: the terms naming a
single sheet resolved perfectly, so the total was a plausible number that was merely wrong.
Nothing errored and nothing refused. With this, that workbook agrees with Excel on all
**1,210,790** of its comparable cells.

## [0.14.0] - 2026-09-19

### Fixed

- **`CellRange(_: String)` could not read a whole span, and produced references off the
  grid.** It split on the colon and handed each half to `CellRef(_:)`, which defaults a
  missing row to 1 and a missing column to **0**:

  | written | was | meant |
  |---|---|---|
  | `A:A` | the single cell `A1` | column A, every row |
  | `A:C` | a plausible 1×3 | three columns, every row |
  | `1:1` | column **0**, row 1 | row 1, every column |
  | `2:5` | column **0**, rows 2–5 | rows 2–5, every column |

  The column cases were wrong. The row cases were worse: columns are 1-based, so
  `CellRange("2:5").rowCount` answered 4 while every reference it enumerated was off the
  grid — the count looked right and the cells could not exist.

  `WorksheetParser` in SwiftXLSX builds ranges this way from four attributes read out of real
  files — an array formula's `ref`, `autoFilter`, `mergeCell`, and a data validation's
  `sqref`. A data validation over a whole column is ordinary.

- **`CellRange("")` trapped.** `split` returns nothing for an empty string and the initialiser
  indexed `parts[0]`. It is non-failable and called with whatever a file said, so it now
  answers `A1` — the point being that it answers at all.

- **A descending span no longer traps.** `C:A` normalises to `A:C`, carrying each `$` with its
  own end. Excel writes spans ascending, so this only arises from a malformed file — where the
  alternative was a range whose `start` is past its `end` and a `cells` call building `3...1`.

### Added

- **`CellRange.wholeSpan(from:to:)`**, public, returning the range a whole-span pair names or
  `nil` if the pair is not one.

  Exposed because this rule had **two implementations and only one was right**.
  `DefinedNameResolver` in SwiftXLSX had worked it out for defined names, which is why
  whole-column names round-tripped across 161,901 of them while `CellRange(_:)` was answering
  `A1` — and why nobody found the defect: the path that mattered most had quietly been fixed
  already, somewhere else. That resolver now delegates here.

## [0.13.0] - 2026-09-19

### Added

- **`FormulaAST.arrayConstant([[FormulaAST]])`** — an array constant written in the formula,
  `{1,2,3;4,5,6}`, held as rows of elements. A comma separates columns and a semicolon
  separates rows, which is the stored file format's spelling rather than the user's: a
  workbook saved in a locale that displays `\` for the row separator still holds `;` in the
  XML, so it is the only spelling a reader ever sees.

  Every row has the same width, and **the parser is what guarantees it** — Excel refuses
  `{1,2;3}` as a syntax error rather than reading a 2×2 with a hole. Only constants go inside:
  numbers, text, booleans and errors, with no references, names, calls or nested arrays. The
  element type is `FormulaAST` regardless, because a negative number arrives as a minus and a
  number and is folded to `.number(-1)` before it lands here.

  `DependencyGraph` reads nothing from one, and deliberately does not recurse into it: the
  grammar is the parser's guarantee, and walking the elements here would imply a reference
  could be found.

  Source-breaking for any exhaustive `switch` over `FormulaAST` outside this package.

## [0.12.0] - 2026-09-17

### Added

- **`FormulaAST.call(_:_:)`** — a call whose callee is an expression rather than a name.
  `function(_:_:)` names what it calls, which covers every formula Excel had before `LAMBDA`,
  and does not cover the immediately-invoked form:

  ```
  LAMBDA(f, n, IF(n<=0, 0, 1 + f(f, n-1)))(LAMBDA(f, n, …), 4094)
  ```

  Not a curiosity. A `LAMBDA` cannot call itself by name without a defined name, and a defined
  name is a manual step — so self-application is how a recursive lambda is written without one,
  and it is what the conformance workbook used to measure Excel's 4,096-invocation limit. A
  corpus workbook writes one for a Box–Muller normal draw, which is how we know Excel accepts
  the form. Currying needs it too: `add(3)(4)` has no name between its two calls.

  Deliberately not `function("", …)`. Every `case .function(let name, _)` downstream keys off
  the name, and an empty one would make all of them wrong in the same silent way.

### Breaking

- `FormulaAST` gains a case, so every exhaustive `switch` over it needs one more arm.


## [0.11.0] - 2026-09-17

### Added

- **`CellValue.lambda(parameters:body:captured:)`** — a function as a value. `LAMBDA` makes
  functions first-class in Excel, and three legal shapes cannot be expressed without it: a
  lambda **returned** by a lambda, **bound** by a `LET`, or **chosen** by an `IF`. Each would
  otherwise evaluate to something plausible rather than to an error, which is the failure a
  workbook checker cannot afford — it reports on other people's files, and a class of formulas
  read wrongly and silently is worse than one it refuses out loud.

  The `captured` frame is not decoration. `LAMBDA(x, LAMBDA(y, x+y))` returns a function that
  must remember `x`; a lambda without a captured frame is not a closure, and currying under
  one does not fail loudly — it returns the wrong answer.

- **`ExcelError.calc` (`#CALC!`)** — what Excel shows for a formula that cannot produce a
  value, most often a `LAMBDA` that was never called. Without it a lambda in a cell had to
  become `#VALUE!`, which is a different thing and says the wrong one.

### Breaking

- `CellValue` gains a case, so every exhaustive `switch` over it needs one more arm. Taken
  deliberately, at a minor version, and after the measured demand had already shipped without
  it — see `PROPOSAL_lambda.md` §7 and §12 in SwiftExcelFunctions.


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

[Unreleased]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.15.0...HEAD
[0.15.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/jpurnell/SwiftExcelCore/compare/v0.10.0...v0.11.0
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
