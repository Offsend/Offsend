import XCTest
@testable import OffsendRuntime

final class InterpreterScriptPathNormalizerTests: XCTestCase {
    func testJoinsAdjacentDoubleQuotedLiterals() {
        XCTAssertEqual(
            InterpreterScriptPathNormalizer.joiningAdjacentStringLiterals(#""c"+"ert"+".p"+"em""#),
            #""cert.pem""#
        )
    }

    func testJoinsAdjacentSingleQuotedLiterals() {
        XCTAssertEqual(
            InterpreterScriptPathNormalizer.joiningAdjacentStringLiterals(#"'s'+'ecrets'"#),
            #"'secrets'"#
        )
    }

    func testJoinsWithWhitespaceAroundPlus() {
        XCTAssertEqual(
            InterpreterScriptPathNormalizer.joiningAdjacentStringLiterals(#""ce" + "rt" + ".pem""#),
            #""cert.pem""#
        )
    }

    func testLeavesFStringsAlone() {
        let source = #"f"cert"+"pem""#
        XCTAssertEqual(
            InterpreterScriptPathNormalizer.joiningAdjacentStringLiterals(source),
            source
        )
    }

    func testLeavesNonLiteralOperandsAlone() {
        let source = #""cert."+ext"#
        XCTAssertEqual(
            InterpreterScriptPathNormalizer.joiningAdjacentStringLiterals(source),
            source
        )
    }

    func testLeavesUnrelatedTextAlone() {
        XCTAssertEqual(
            InterpreterScriptPathNormalizer.joiningAdjacentStringLiterals(#""hello"+"world""#),
            #""helloworld""#
        )
        XCTAssertEqual(
            InterpreterScriptPathNormalizer.joiningAdjacentStringLiterals("print(1+2)"),
            "print(1+2)"
        )
    }

    func testJoinsInsidePythonPathExpression() {
        let source = #"Path("c"+"ert"+".p"+"em")"#
        XCTAssertEqual(
            InterpreterScriptPathNormalizer.joiningAdjacentStringLiterals(source),
            #"Path("cert.pem")"#
        )
    }
}
