//
//  FileNameSanitizerTests.swift
//  StoriTests
//
//  Unit tests for sanitizeFileName - security-sensitive filename sanitization
//

import XCTest
@testable import Stori

final class FileNameSanitizerTests: XCTestCase {

    // MARK: - Normal / Safe Names

    func testSafeNameUnchanged() {
        XCTAssertEqual(sanitizeFileName("MyProject"), "MyProject")
        XCTAssertEqual(sanitizeFileName("Track_01"), "Track_01")
        XCTAssertEqual(sanitizeFileName("Export-2024"), "Export-2024")
    }

    func testUnicodeNamePreserved() {
        XCTAssertEqual(sanitizeFileName("Café"), "Café")
        XCTAssertEqual(sanitizeFileName("プロジェクト"), "プロジェクト")
    }

    // MARK: - Whitespace

    func testLeadingTrailingWhitespaceTrimmed() {
        XCTAssertEqual(sanitizeFileName("  Project  "), "Project")
        XCTAssertEqual(sanitizeFileName("\t\nName\n\t"), "Name")
    }

    func testLeadingTrailingDotsAndUnderscoresTrimmed() {
        XCTAssertEqual(sanitizeFileName("..hidden"), "hidden")
        XCTAssertEqual(sanitizeFileName("name__"), "name")
        XCTAssertEqual(sanitizeFileName("._.file._."), "file")
    }

    // MARK: - Security: Null Bytes

    func testNullBytesRemoved() {
        XCTAssertEqual(sanitizeFileName("Project\0Name"), "ProjectName")
        XCTAssertEqual(sanitizeFileName("\0\0Only"), "Only")
    }

    // MARK: - Security: Control Characters

    func testControlCharactersRemoved() {
        // 0x00-0x1F and 0x7F removed; 0x20 (space) and printable ASCII kept
        let withControl = "Proj\u{01}ect\u{7f}Name"
        XCTAssertEqual(sanitizeFileName(withControl), "ProjectName")
    }

    func testTabAndNewlineRemoved() {
        XCTAssertEqual(sanitizeFileName("Proj\tect\nName"), "ProjectName")
    }

    // MARK: - Security: Path Traversal

    func testPathTraversalSequencesRemoved() {
        XCTAssertEqual(sanitizeFileName("..parent"), "parent")
        XCTAssertEqual(sanitizeFileName("dir./file"), "dirfile")
        XCTAssertEqual(sanitizeFileName(".\\windows"), "windows")
        XCTAssertEqual(sanitizeFileName("a..b"), "ab")
    }

    // MARK: - Invalid Filename Characters

    func testInvalidCharsReplacedWithUnderscore() {
        XCTAssertEqual(sanitizeFileName("a:b"), "a_b")
        XCTAssertEqual(sanitizeFileName("a/b"), "a_b")
        XCTAssertEqual(sanitizeFileName("a\\b"), "a_b")
        XCTAssertEqual(sanitizeFileName("a?b"), "a_b")
        XCTAssertEqual(sanitizeFileName("a*b"), "a_b")
        XCTAssertEqual(sanitizeFileName("a|b"), "a_b")
        XCTAssertEqual(sanitizeFileName("a\"b"), "a_b")
        XCTAssertEqual(sanitizeFileName("a<b>c"), "a_b_c")
        XCTAssertEqual(sanitizeFileName("a%b"), "a_b")
    }

    func testMultipleInvalidChars() {
        // Trailing underscore is trimmed by leading/trailing ._ trim
        XCTAssertEqual(sanitizeFileName("C:/Projects/My*File?"), "C__Projects_My_File")
    }

    // MARK: - Reserved Windows Names

    func testReservedWindowsNamesPrefixedWithUnderscore() {
        XCTAssertEqual(sanitizeFileName("CON"), "_CON")
        XCTAssertEqual(sanitizeFileName("PRN"), "_PRN")
        XCTAssertEqual(sanitizeFileName("AUX"), "_AUX")
        XCTAssertEqual(sanitizeFileName("NUL"), "_NUL")
        XCTAssertEqual(sanitizeFileName("COM1"), "_COM1")
        XCTAssertEqual(sanitizeFileName("COM9"), "_COM9")
        XCTAssertEqual(sanitizeFileName("LPT1"), "_LPT1")
        XCTAssertEqual(sanitizeFileName("LPT9"), "_LPT9")
    }

    func testReservedNameCaseInsensitive() {
        XCTAssertEqual(sanitizeFileName("con"), "_con")
        XCTAssertEqual(sanitizeFileName("nul"), "_nul")
    }

    // MARK: - Empty Result

    func testEmptyAfterSanitizationBecomesUntitled() {
        XCTAssertEqual(sanitizeFileName(""), "Untitled")
        XCTAssertEqual(sanitizeFileName("   "), "Untitled")
        XCTAssertEqual(sanitizeFileName("...."), "Untitled")
        XCTAssertEqual(sanitizeFileName("::::"), "Untitled")
        XCTAssertEqual(sanitizeFileName("\0\0\0"), "Untitled")
    }

    // MARK: - Length Cap

    func testLongNameTruncatedTo200() {
        let long = String(repeating: "a", count: 300)
        let result = sanitizeFileName(long)
        XCTAssertEqual(result.count, 200)
        XCTAssertTrue(result.allSatisfy { $0 == "a" })
    }

    func testNameAt200CharactersUnchanged() {
        let exactly200 = String(repeating: "x", count: 200)
        XCTAssertEqual(sanitizeFileName(exactly200), exactly200)
    }

    // MARK: - Unicode Normalization

    func testUnicodeNormalizationApplied() {
        // é as single codepoint (U+00E9) vs e + combining acute (U+0065 U+0301) both normalize to same NFC form
        let precomposed = "Café"
        let decomposed = "Cafe\u{0301}"
        XCTAssertEqual(sanitizeFileName(precomposed), sanitizeFileName(decomposed))
    }
}
