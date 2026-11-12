import std/unittest
import std/json
import std/options
import std/strutils
import core/gateway/gateway
import core/gateway/gateway_types
import core/results

suite "jsonParseSafe contract":
  test "parses valid JSON":
    let result = jsonParseSafe("{\"key\": \"value\"}")
    check result.isOk()
    check result.get["key"].getStr() == "value"

  test "returns err for invalid JSON":
    let result = jsonParseSafe("not json")
    check result.isErr()

  test "returns err for empty string":
    let result = jsonParseSafe("")
    check result.isErr()

  test "returns err for invalid JSON — regression DEBT#282":
    let result = jsonParseSafe("{invalid")
    check result.isErr()

  test "returns ok for valid JSON — regression DEBT#282":
    let result = jsonParseSafe("{\"key\": \"value\"}")
    check result.isOk()
    check result.get["key"].getStr() == "value"

suite "jsonRequireObject contract":
  test "accepts JSON object":
    let result = jsonRequireObject(%*{"a": 1})
    check result.isOk()

  test "rejects JSON array":
    let result = jsonRequireObject(%*[1, 2])
    check result.isErr()

  test "rejects JSON string":
    let result = jsonRequireObject(%*"hello")
    check result.isErr()

suite "jsonRequireObjectField contract":
  test "returns field when present and is object":
    let result = jsonRequireObjectField(%*{"a": {"nested": 1}}, "a")
    check result.isOk()
    check result.get["nested"].getInt() == 1

  test "returns err when missing":
    let result = jsonRequireObjectField(%*{"a": 1}, "b")
    check result.isErr()

suite "jsonGetNonEmptyStringField contract":
  test "returns string when present and non-empty":
    let result = jsonGetNonEmptyStringField(%*{"name": "test"}, "name")
    check result.isOk()
    check result.get == "test"

  test "returns err when empty":
    let result = jsonGetNonEmptyStringField(%*{"name": ""}, "name")
    check result.isErr()

  test "returns err when missing":
    let result = jsonGetNonEmptyStringField(%*{}, "name")
    check result.isErr()

suite "jsonGetBoolFieldOrDefault contract":
  test "returns bool when present":
    let result = jsonGetBoolFieldOrDefault(%*{"active": true}, "active", false)
    check result.isOk()
    check result.get == true

  test "returns default when missing":
    let result = jsonGetBoolFieldOrDefault(%*{}, "active", true)
    check result.isOk()
    check result.get == true

suite "gatekeepNumericInput contract":
  test "value within range returns ok":
    let cRes = makeConstraintDefinition(options.some(0), options.some(10))
    check cRes.isOk()
    let result = gatekeepNumericInput(5, cRes.get)
    check result.isOk()
    check result.get == 5

  test "value below min returns err":
    let cRes = makeConstraintDefinition(options.some(0), options.some(10))
    check cRes.isOk()
    let result = gatekeepNumericInput(-1, cRes.get)
    check result.isErr()

  test "value above max returns err":
    let cRes = makeConstraintDefinition(options.some(0), options.some(10))
    check cRes.isOk()
    let result = gatekeepNumericInput(11, cRes.get)
    check result.isErr()

suite "emitTypeConstraintAsSmt contract":
  test "emits range type constraint with bounds":
    let c = TypeConstraint(kind: tcRange, varName: "x", lowerBound: some(0), upperBound: some(10))
    let smt = emitTypeConstraintAsSmt(c)
    check smt.contains("x")
    check smt.contains(">=")
    check smt.contains("<=")

  test "emits non-empty string constraint":
    let c = TypeConstraint(kind: tcNonEmpty, varName: "s", smtSort: "String")
    let smt = emitTypeConstraintAsSmt(c)
    check smt.contains("s")
    check smt.contains("str.len")
