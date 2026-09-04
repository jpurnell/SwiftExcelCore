# ``SwiftExcelCore``

The vocabulary a spreadsheet is described in.

## Overview

What a cell holds, where it sits, what a formula says, and what went wrong — and nothing else.

This package exists so that packages which must agree about those things do not have to depend on
each other to do it. A function library that evaluates `VLOOKUP` and a file reader that parses
`=VLOOKUP(...)` both need a cell reference and a cell value; neither needs the other. Without a
shared vocabulary one would have to import the other, and the dependency would run the wrong way.

It is Foundation-only, and stays that way: a dependency taken here is a dependency taken by
everything downstream.

## What is not here

Parsing and file storage belong to SwiftXLSX — producing a formula tree from text is syntax.
Function implementations and evaluation belong to SwiftExcelFunctions. Styles and layout are
presentation. Anything opinionated belongs a layer up, because this package is only useful while
it holds still.
