# SwiftExcelCore Master Plan

**Purpose:** Source of truth for project vision, architecture, and goals.

Derived from `BusinessMathExcel/project/plans/proposals/PROPOSAL_swift_excel_architecture.md`,
which decided the family this package belongs to and why it was separated.

---

## Project Overview

### Mission

The vocabulary a spreadsheet is described in: what a cell holds, where it sits, what a formula
says, and what went wrong. Nothing else.

This package exists so that three packages that must agree about those things do not have to
depend on each other to do it. A function library that evaluates `VLOOKUP` and a file reader that
parses `=VLOOKUP(...)` both need `CellRef` and `CellValue`; neither needs the other.

### Target Users

- **SwiftXLSX** — reading and writing `.xlsx`, which produces and consumes these types.
- **SwiftExcelFunctions** — evaluating formulas, which computes over these types.
- Any future layout, theming, or diffing package in the family.
- Directly, by anyone modelling spreadsheet data who wants the vocabulary without a file format.

### Key Differentiators

- **Foundation only.** No ZIP, no numerics, no network. A dependency of this package is a
  dependency of everything downstream, so it takes none it can avoid.
- **Value types and one protocol.** No behaviour worth arguing about, which is what lets it stay
  still while the packages above it move.

---

## Architecture

### Technology Stack

- **Language:** Swift 6.0+, strict concurrency, everything `Sendable`
- **Build System:** Swift Package Manager
- **Dependencies:** Foundation, and the DocC plugin

### What lives here

| Type | Why it is core |
|---|---|
| `CellValue` | what a cell holds — number, text, bool, error, formula, date, blank, array |
| `ExcelError` | `#DIV/0!`, `#N/A`, `#REF!` — produced by evaluation, stored by the file |
| `EvalError` | how evaluation fails, distinct from what Excel records |
| `CellRef`, `CellRange` | where a cell is, and a rectangle of them |
| `CellAddress`, `SheetReference` | the same, qualified by sheet |
| `FormulaAST` | what a formula says, independent of how it was written or stored |
| `CellValueProvider` | the protocol by which anything reads cells — the seam that lets the function library work without a workbook |
| `NamedRange` | a name bound to a target, which both the file and the evaluator resolve |

### What deliberately does not

- **Parsing and serialization** — SwiftXLSX. Producing a `FormulaAST` from text is syntax.
- **Function implementations and evaluation** — SwiftExcelFunctions.
- **Styles, fonts, fills** — presentation, and eventually its own package.
- **Anything opinionated.** Three packages depend on this one, so every change here is a
  three-repository release. That cost is only bearable if changes are rare.

---

## Current Status

**Pre-release.** Scaffolded 2026-09-04. The types exist today inside SwiftXLSX and move here
unchanged; this is an extraction, not a design exercise.

- [ ] Extract the types listed above from SwiftXLSX, unchanged
- [ ] Port their tests
- [ ] Quality gate 0/0
- [ ] Tag `v0.1.0`
- [ ] SwiftXLSX `0.12.0` depends on it

---

## Priorities

1. **Extract without changing.** Any improvement made during the move is a change whose blame is
   hidden inside a large diff. Move first, improve after, in separate commits.
2. **Keep the surface small.** Every type added here is one three repositories must agree on.
3. **Stay Foundation-only.** The first dependency added is the one that makes this package
   expensive for everyone downstream.

---

## Roadmap

- **v0.1.0** — the extraction, tests passing, gate clean.
- **v0.2.0** — whatever the first real consumer proves is missing, and nothing that is merely
  anticipated.

Deliberately **not** planned: a value-coercion layer, a formula printer, an evaluation protocol.
Each has an obvious home one layer up, and putting it here would make this package hard to change
for the benefit of one caller.

---

**Last Updated:** 2026-09-04 — created. Scope taken from the architecture proposal; nothing
implemented yet.
