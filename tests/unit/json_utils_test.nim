import std/unittest
import std/json
import std/strutils
import core/json/json_utils

suite "jsonNodeStringArray contract":
  test "empty seq produces empty JSON array":
    let arr = jsonNodeStringArray(@[])
    check arr.kind == JArray
    check arr.len == 0

  test "non-empty seq preserves order":
    let arr = jsonNodeStringArray(@["a", "b", "c"])
    check arr.len == 3
    check arr[0].getStr() == "a"
    check arr[1].getStr() == "b"
    check arr[2].getStr() == "c"

  test "handles empty strings":
    let arr = jsonNodeStringArray(@["", "x", ""])
    check arr.len == 3
    check arr[0].getStr() == ""
    check arr[1].getStr() == "x"

suite "jsonArrayToStringSeq contract":
  test "converts JSON array to string seq":
    let node = %*["a", "b", "c"]
    let resultSeq = jsonArrayToStringSeq(node)
    let expected: seq[string] = @["a", "b", "c"]
    check resultSeq == expected

  test "empty JSON array returns empty seq":
    let node = newJArray()
    let resultSeq = jsonArrayToStringSeq(node)
    check resultSeq.len == 0

  test "non-array node returns empty seq":
    let node = %*{"key": "value"}
    let resultSeq = jsonArrayToStringSeq(node)
    check resultSeq.len == 0

  test "filters non-string elements":
    let node = %*["a", 123, "b", true]
    let resultSeq = jsonArrayToStringSeq(node)
    let expected: seq[string] = @["a", "b"]
    check resultSeq == expected

suite "normalizedStringSeq contract":
  test "strips and filters empty strings":
    let raw = @["  a  ", "", "  b  ", "   ", "c"]
    let norm = normalizedStringSeq(raw)
    let expected: seq[string] = @["a", "b", "c"]
    check norm == expected

  test "empty input returns empty output":
    let result = normalizedStringSeq(@[])
    check result.len == 0

  test "all empty strings returns empty output":
    let result = normalizedStringSeq(@["", "   ", ""])
    check result.len == 0

suite "renderJsonMultiline contract":
  test "renders object with indentation":
    let node = %*{"key": "value"}
    let rendered = renderJsonMultiline(node)
    check rendered.contains("key")
    check rendered.contains("value")

  test "renders array across lines":
    let node = %*["a", "b"]
    let rendered = renderJsonMultiline(node)
    check rendered.contains("a")
    check rendered.contains("b")
