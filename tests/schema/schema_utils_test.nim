## Tests for schema_utils.nim — compile-time and runtime validation.
##
## The compile-time macro test (loadPolicyTypes) is embedded as a static block
## so that the compiler itself exercises the macro and we get a hard failure
## if validation logic is broken. Runtime tests use std/unittest.

import std/[unittest, json, strutils]
import core/schema/schema_utils

# ---------------------------------------------------------------------------
# Compile-Time Validation Test (static block)
# ---------------------------------------------------------------------------
# The macro must pass at compile time — any violation would be a compiler error.

static:
  # The macro receives the schema as AST (NimNode), so we must inline
  # the constructor expression — macro parameters cannot resolve const refs.

  # Valid single object — must compile without error
  discard loadPolicyTypes(
    (name: "alpha", count: 42, enabled: true),
    mkSchema("testSchema", "axiom.schema.v1", @[
      mkField("name", pfkString, required = true),
      mkField("count", pfkInt, required = true),
      mkField("enabled", pfkBool, required = false),
    ])
  )

  # Valid array of objects — must compile without error
  discard loadPolicyTypes(
    @[(name: "alpha", count: 1), (name: "beta", count: 2)],
    mkSchema("testSchema", "axiom.schema.v1", @[
      mkField("name", pfkString, required = true),
      mkField("count", pfkInt, required = true),
      mkField("enabled", pfkBool, required = false),
    ])
  )

# ---------------------------------------------------------------------------
# Runtime Tests
# ---------------------------------------------------------------------------

suite "AxiomSchemaVersion":
  test "version string is defined and non-empty":
    check AxiomSchemaVersion.len > 0
    check AxiomSchemaVersion == "axiom.schema.v1"

suite "SchemaViolation string conversion":
  test "$ViolationSeverity produces correct strings":
    check $vsError == "error"
    check $vsWarning == "warning"

  test "$SchemaViolation includes severity and field path":
    let sv = SchemaViolation(
      severity: vsError,
      schemaName: "mySchema",
      fieldPath: "config.version",
      message: "required field missing",
      line: 10, column: 5
    )
    let s = $sv
    check "[error]" in s
    check "mySchema.config.version" in s
    check "required field missing" in s
    check ":10:5" in s

  test "$PolicyFieldKind produces correct strings":
    check $pfkString == "string"
    check $pfkInt == "int"
    check $pfkFloat == "float"
    check $pfkBool == "bool"
    check $pfkArray == "array"
    check $pfkObject == "object"

suite "Schema Construction Helpers":
  test "mkField creates correct spec":
    let f = mkField("version", pfkString, required = true, minLength = 1)
    check f.name == "version"
    check f.kind == pfkString
    check f.required == true
    check f.minLength == 1
    check f.maxLength == 0

  test "mkSchema creates correct schema":
    let s = mkSchema("test", "v1", @[mkField("x", pfkInt)])
    check s.name == "test"
    check s.version == "v1"
    check s.fields.len == 1
    check s.fields[0].name == "x"

suite "validatePolicyConfig — string fields":
  test "valid string passes":
    let schema = mkSchema("s", "v1", @[mkField("name", pfkString)])
    let config = %* {"name": "hello"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 0

  test "missing required string produces violation":
    let schema = mkSchema("s", "v1", @[mkField("name", pfkString)])
    let config = %* {"other": "value"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1
    check violations[0].severity == vsError
    check violations[0].fieldPath == "name"
    check "required field missing" in violations[0].message

  test "empty required string produces violation":
    let schema = mkSchema("s", "v1", @[mkField("name", pfkString)])
    let config = %* {"name": ""}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1
    check "empty" in violations[0].message

  test "string too short produces violation":
    let schema = mkSchema("s", "v1", @[mkField("name", pfkString, minLength = 3)])
    let config = %* {"name": "ab"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1
    check "minimum" in violations[0].message

  test "string too long produces violation":
    let schema = mkSchema("s", "v1", @[mkField("name", pfkString, maxLength = 2)])
    let config = %* {"name": "abc"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1
    check "maximum" in violations[0].message

  test "string not in allowed values produces violation":
    let schema = mkSchema("s", "v1", @[
      mkField("color", pfkString, allowedValues = @["red", "blue"])
    ])
    let config = %* {"color": "green"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1
    check "not in allowed set" in violations[0].message

  test "string in allowed values passes":
    let schema = mkSchema("s", "v1", @[
      mkField("color", pfkString, allowedValues = @["red", "blue"])
    ])
    let config = %* {"color": "red"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 0

  test "wrong type for string field produces violation":
    let schema = mkSchema("s", "v1", @[mkField("name", pfkString)])
    let config = %* {"name": 42}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1
    check "expected string" in violations[0].message

  test "optional string field missing is OK":
    let schema = mkSchema("s", "v1", @[
      mkField("opt", pfkString, required = false)
    ])
    let config = %* {"other": "value"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 0

suite "validatePolicyConfig — int fields":
  test "valid int passes":
    let schema = mkSchema("s", "v1", @[mkField("count", pfkInt)])
    let config = %* {"count": 42}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 0

  test "wrong type for int field produces violation":
    let schema = mkSchema("s", "v1", @[mkField("count", pfkInt)])
    let config = %* {"count": "not an int"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1
    check "expected int" in violations[0].message

  test "missing required int produces violation":
    let schema = mkSchema("s", "v1", @[mkField("count", pfkInt)])
    let config = %* {"other": 1}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1

suite "validatePolicyConfig — float fields":
  test "valid float passes":
    let schema = mkSchema("s", "v1", @[mkField("ratio", pfkFloat)])
    let config = %* {"ratio": 3.14}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 0

  test "int accepted as float":
    let schema = mkSchema("s", "v1", @[mkField("ratio", pfkFloat)])
    let config = %* {"ratio": 42}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 0

  test "wrong type for float produces violation":
    let schema = mkSchema("s", "v1", @[mkField("ratio", pfkFloat)])
    let config = %* {"ratio": "pi"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1

suite "validatePolicyConfig — bool fields":
  test "valid bool passes":
    let schema = mkSchema("s", "v1", @[mkField("flag", pfkBool)])
    let config = %* {"flag": true}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 0

  test "wrong type for bool produces violation":
    let schema = mkSchema("s", "v1", @[mkField("flag", pfkBool)])
    let config = %* {"flag": 1}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1

suite "validatePolicyConfig — array fields":
  test "valid array passes":
    let schema = mkSchema("s", "v1", @[mkField("items", pfkArray)])
    let config = %* {"items": ["a", "b"]}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 0

  test "wrong type for array produces violation":
    let schema = mkSchema("s", "v1", @[mkField("items", pfkArray)])
    let config = %* {"items": "not array"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1

suite "validatePolicyConfig — object fields":
  test "valid object passes":
    let schema = mkSchema("s", "v1", @[mkField("meta", pfkObject)])
    let config = %* {"meta": {"key": "val"}}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 0

  test "wrong type for object produces violation":
    let schema = mkSchema("s", "v1", @[mkField("meta", pfkObject)])
    let config = %* {"meta": [1, 2, 3]}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 1

suite "validatePolicyConfig — multiple violations":
  test "collects all violations at once":
    let schema = mkSchema("s", "v1", @[
      mkField("name", pfkString),
      mkField("count", pfkInt),
      mkField("flag", pfkBool),
    ])
    let config = %* {"wrong_field": "oops"}
    let violations = validatePolicyConfig(config, schema)
    check violations.len == 3
    # All should be errors
    for v in violations:
      check v.severity == vsError

suite "validateAll — batch validation":
  test "empty validators returns empty":
    let validators: seq[SchemaValidator] = @[]
    let violations = validateAll(validators)
    check violations.len == 0

  test "aggregates violations from multiple validators":
    let schema = mkSchema("s", "v1", @[mkField("x", pfkString)])
    let badConfig = %* {"y": 1}
    let goodConfig = %* {"x": "ok"}

    let validators = @[
      SchemaValidator(schema: schema, config: badConfig, label: "bad"),
      SchemaValidator(schema: schema, config: goodConfig, label: "good"),
    ]
    let violations = validateAll(validators)
    check violations.len == 1
    check violations[0].fieldPath == "x"

  test "convenience overload validates config/schema pairs":
    let schema = mkSchema("s", "v1", @[mkField("x", pfkInt)])
    let badConfig = %* {"x": "not int"}
    let goodConfig = %* {"x": 42}

    let violations = validateAll(@[badConfig, goodConfig], @[schema])
    check violations.len == 1

  test "convenience overload with fewer schemas reuses last":
    let s1 = mkSchema("s1", "v1", @[mkField("a", pfkString)])
    let s2 = mkSchema("s2", "v1", @[mkField("b", pfkInt)])
    let c1 = %* {"a": "ok"}
    let c2 = %* {"b": "not int"}
    let c3 = %* {"b": 99}

    # 3 configs, 2 schemas — c3 validated against s2 (last)
    let violations = validateAll(@[c1, c2, c3], @[s1, s2])
    check violations.len == 1  # only c2 fails against s2
