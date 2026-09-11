# SwiftExcelCore

Part of the SwiftExcel package family. See `project/master_plan.md` for scope and roadmap, and
`BusinessMathExcel/project/plans/proposals/PROPOSAL_swift_excel_architecture.md` for why the
family is split the way it is.

**Status:** pre-release, scaffolded 2026-09-04. Nothing implemented yet.

## The family

| Package | Holds |
|---|---|
| **SwiftExcelCore** | the vocabulary — `CellValue`, `CellRef`, `FormulaAST`, `ExcelError`, `CellValueProvider` |
| **SwiftXLSX** | syntax and storage — lexer, parser, serializer, reader/writer, styles |
| **SwiftExcelFunctions** | the function library and evaluator |
| **BusinessMath** | the mathematics, and only the mathematics |

## Building

```
swift build && swift test
```

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Permissive deliberately. This is shared plumbing: it is more useful the more
widely it is used, and it carries no copyleft. The copyleft layers of the family
(SwiftExcelFunctions, BusinessMath, BusinessMathExcel) are AGPLv3 with a
commercial option; copyleft may depend on permissive, never the reverse.
