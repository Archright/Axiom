import std/unittest
import core/text/text_utils

suite "sanitizeToken contract":
  test "preserves alphanumeric and underscore":
    check sanitizeToken("abc_123") == "abc_123"

  test "replaces spaces with underscores":
    check sanitizeToken("hello world") == "hello_world"

  test "replaces hyphens with underscores":
    check sanitizeToken("hello-world") == "hello_world"

  test "replaces special chars with underscores individually":
    check sanitizeToken("a!@#b") == "a___b"

  test "empty string returns unknown":
    check sanitizeToken("") == "unknown"

  test "all special chars returns single underscore each":
    check sanitizeToken("!@#$%") == "_____"

  test "does not trim leading or trailing underscores":
    check sanitizeToken("_hello_") == "_hello_"

  test "does not collapse consecutive underscores":
    check sanitizeToken("a___b") == "a___b"

  test "prefixes digit-starting tokens with f_":
    check sanitizeToken("123abc") == "f_123abc"

  test "whitespace-only returns unknown":
    check sanitizeToken("   ") == "unknown"

suite "leadingWhitespace contract":
  test "extracts leading spaces":
    check leadingWhitespace("  hello") == "  "

  test "extracts mixed spaces and tabs":
    check leadingWhitespace(" \t hello") == " \t "

  test "no leading whitespace returns empty":
    check leadingWhitespace("hello") == ""
