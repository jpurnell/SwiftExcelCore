import Testing
@testable import SwiftExcelCore

/// The package is reachable and reports itself.
///
/// A placeholder until the types are extracted from SwiftXLSX, and deliberately
/// trivial: a test target with no tests passes by having nothing to say, which
/// reads the same as passing.
@Test func theModuleIsImportable() {
    #expect(!SwiftExcelCore.version.isEmpty)
}
