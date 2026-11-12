import std/unittest
import std/json
import verification/analyzer/analyzer_shared_json
import core/types/certificate_types

suite "analyzer_shared_json - JSON utilities":
  test "mergeStringEvidence empty inputs":
    let primary: seq[string] = @[]
    let secondary: seq[string] = @[]
    let result = mergeStringEvidence(primary, secondary)
    check result.len == 0

  test "mergeStringEvidence deduplicates and preserves order":
    let primary = @["a", "b", "duplicate"]
    let secondary = @["b", "c", "duplicate"]
    let result = mergeStringEvidence(primary, secondary)
    check result.len == 4
    check result[0] == "a"
    check result[1] == "b"
    check result[2] == "duplicate"
    check result[3] == "c"

  test "mergeStringEvidence filters empty strings":
    let primary = @["a", "", "b"]
    let secondary = @["", "c"]
    let result = mergeStringEvidence(primary, secondary)
    check result == @["a", "b", "c"]

  test "keyToStatus maps green variants":
    check keyToStatus("green") == certGreen
    check keyToStatus("certGreen") == certGreen

  test "keyToStatus does not promote ambiguous success strings to certGreen":
    # P0: ambiguous legacy success strings carry no provenance tier and must
    # never overclaim dual (Z3 ∧ Lean) assurance — they map to the neutral
    # certPending; the caller reconciles against stored evidence.
    check keyToStatus("ok") == certPending
    check keyToStatus("verified") == certPending
    check keyToStatus("pass") == certPending
    check keyToStatus("passed") == certPending

  test "keyToStatus maps pending variants":
    check keyToStatus("pending") == certPending
    check keyToStatus("certPending") == certPending
    check keyToStatus("review") == certPending
    check keyToStatus("needs_review") == certPending

  test "keyToStatus maps red variants":
    check keyToStatus("red") == certRed
    check keyToStatus("certRed") == certRed
    check keyToStatus("failed") == certRed
    check keyToStatus("fail") == certRed

  test "keyToStatus maps other statuses":
    check keyToStatus("yellow") == certYellow
    check keyToStatus("certYellow") == certYellow
    check keyToStatus("bounded") == certYellow
    check keyToStatus("partial") == certYellow
    check keyToStatus("stale") == certStale
    check keyToStatus("certStale") == certStale
    check keyToStatus("axiom") == certVerifiedAxiom
    check keyToStatus("verifiedaxiom") == certVerifiedAxiom

  test "keyToStatus unknown returns certRed":
    check keyToStatus("unknown_status") == certRed
    check keyToStatus("") == certRed
    check keyToStatus("random") == certRed

  test "toStringList extracts strings from array":
    let node = %*["  a  ", "b", "c"]
    let result = toStringList(node)
    check result == @["a", "b", "c"]

  test "toStringList extracts and deduplicates":
    let node = %*["a", "b", "a", "c", "b"]
    let result = toStringList(node)
    check result.len == 3
    check result == @["a", "b", "c"]

  test "toStringList filters empty strings":
    let node = %*["", "a", "  ", "b", ""]
    let result = toStringList(node)
    check result == @["a", "b"]

  test "toStringList handles non-array":
    let node = %*{"key": "value"}
    let result = toStringList(node)
    check result.len == 0

  test "firstStringField finds value":
    var node = %*{"name": "test_value", "other": 123}
    check firstStringField(node, @["name"]) == "test_value"
    check firstStringField(node, @["other", "name"]) == "test_value"

  test "firstStringField returns empty for missing":
    var node = %*{"other": 123}
    check firstStringField(node, @["name"]) == ""

  test "firstStringField strips whitespace":
    var node = %*{"name": "  trimmed  "}
    check firstStringField(node, @["name"]) == "trimmed"

  test "firstStringField returns empty for non-string":
    var node = %*{"name": 123}
    check firstStringField(node, @["name"]) == ""

  test "firstBoolField finds value true":
    var node = %*{"flag": true, "other": 123}
    check firstBoolField(node, @["flag"], false) == true
    check firstBoolField(node, @["other", "flag"], false) == true

  test "firstBoolField returns default for missing":
    var node = %*{"other": 123}
    check firstBoolField(node, @["flag"], true) == true
    check firstBoolField(node, @["flag"], false) == false

  test "firstBoolField handles false value":
    var node = %*{"flag": false}
    check firstBoolField(node, @["flag"], true) == false

  test "firstArrayField returns string array":
    var node = %*{"items": ["x", "y", "z"]}
    let result = firstArrayField(node, @["items"])
    check result == @["x", "y", "z"]

  test "firstArrayField returns empty for missing":
    var node = %*{"other": 123}
    let result: seq[string] = firstArrayField(node, @["items"])
    check result.len == 0

  test "firstArrayField returns empty for non-array":
    var node = %*{"items": "not_an_array"}
    let result: seq[string] = firstArrayField(node, @["items"])
    check result.len == 0

  test "firstIntField finds integer value":
    var node = %*{"count": 42, "other": "hello"}
    check firstIntField(node, @["count"], 0) == 42

  test "firstIntField returns default for missing":
    var node = %*{"other": "hello"}
    check firstIntField(node, @["count"], 99) == 99

  test "firstIntField handles zero default":
    let emptyNode: JsonNode = newJObject()
    check firstIntField(emptyNode, @["x"], 0) == 0

  test "firstIntField finds first matching key":
    var node = %*{"count": 42, "other": 99}
    check firstIntField(node, @["other", "count"], 0) == 99

  test "isPreludeOnlyVerifiedAxiom matches status and reason":
    var cert1 = FunctionCertificate(status: certVerifiedAxiom, reason: "verified-axiom:nim.ast.parse.failed.isolated")
    check isPreludeOnlyVerifiedAxiom(cert1) == true

    var cert2 = FunctionCertificate(status: certGreen)
    check isPreludeOnlyVerifiedAxiom(cert2) == false

    var cert3 = FunctionCertificate(status: certVerifiedAxiom, reason: "other.reason")
    check isPreludeOnlyVerifiedAxiom(cert3) == false
