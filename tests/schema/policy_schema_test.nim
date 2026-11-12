import std/unittest
import std/strutils
import std/tables
import core/schema/policy_schema

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func makeValidRule(id = "rule-1", desc = "A test rule"): PolicyRule =
  PolicyRule(
    id: id,
    description: desc,
    selector: {"scope": "gateway"}.toTable,
    deny: @["bad/action"],
    require: @["good/resource"],
    priority: 100,
  )

func makeValidSpec(): PolicySpec =
  PolicySpec(
    version: initPolicyVersion("1.0.0"),
    rules: @[makeValidRule()],
    exemptions: initTable[string, seq[string]](),
    enforcement: peError,
  )

func makeValidConfig(): PolicyConfig =
  PolicyConfig(
    version: initPolicyVersion("1.0.0"),
    spec: makeValidSpec(),
    loadedAt: "2026-06-18T00:00:00Z",
    loadedFrom: "/etc/axiom/policy.json",
  )

# ---------------------------------------------------------------------------
# GateMode
# ---------------------------------------------------------------------------

suite "GateMode":
  test "enum values exist and have correct ordinals":
    check ord(gmShadow) == 0
    check ord(gmAdvisory) == 1
    check ord(gmEnforce) == 2

  test "$ produces expected strings":
    check $gmShadow == "shadow"
    check $gmAdvisory == "advisory"
    check $gmEnforce == "enforce"

  test "parseGateMode round-trips":
    check parseGateMode("shadow") == gmShadow
    check parseGateMode("advisory") == gmAdvisory
    check parseGateMode("enforce") == gmEnforce

  test "parseGateMode falls back to shadow on unknown":
    check parseGateMode("bogus") == gmShadow
    check parseGateMode("") == gmShadow

# ---------------------------------------------------------------------------
# PolicyEnforcement
# ---------------------------------------------------------------------------

suite "PolicyEnforcement":
  test "enum values exist and have correct ordinals":
    check ord(peWarn) == 0
    check ord(peError) == 1
    check ord(peHalt) == 2

  test "$ produces expected strings":
    check $peWarn == "warn"
    check $peError == "error"
    check $peHalt == "halt"

  test "parsePolicyEnforcement round-trips":
    check parsePolicyEnforcement("warn") == peWarn
    check parsePolicyEnforcement("error") == peError
    check parsePolicyEnforcement("halt") == peHalt

  test "parsePolicyEnforcement falls back to warn on unknown":
    check parsePolicyEnforcement("bogus") == peWarn
    check parsePolicyEnforcement("") == peWarn

# ---------------------------------------------------------------------------
# PolicyVersion
# ---------------------------------------------------------------------------

suite "PolicyVersion":
  test "initPolicyVersion and $ round-trip":
    let v = initPolicyVersion("2.1.0")
    check $v == "2.1.0"

  test "equality works":
    let a = initPolicyVersion("1.0.0")
    let b = initPolicyVersion("1.0.0")
    let c = initPolicyVersion("2.0.0")
    check a == b
    check not (a == c)

# ---------------------------------------------------------------------------
# PolicyRule instantiation
# ---------------------------------------------------------------------------

suite "PolicyRule":
  test "can be constructed with all fields":
    let rule = makeValidRule()
    check rule.id == "rule-1"
    check rule.description == "A test rule"
    check rule.selector["scope"] == "gateway"
    check rule.deny.len == 1
    check rule.require.len == 1
    check rule.priority == 100

  test "selector table is accessible":
    var rule = makeValidRule()
    rule.selector["env"] = "prod"
    check rule.selector.len == 2
    check rule.selector["env"] == "prod"

# ---------------------------------------------------------------------------
# PolicySpec instantiation
# ---------------------------------------------------------------------------

suite "PolicySpec":
  test "can be constructed with valid data":
    let spec = makeValidSpec()
    check $spec.version == "1.0.0"
    check spec.rules.len == 1
    check spec.rules[0].id == "rule-1"
    check spec.enforcement == peError

  test "exemptions table is accessible":
    var spec = makeValidSpec()
    spec.exemptions["intent-gate"] = @["rule-1"]
    check spec.exemptions["intent-gate"].len == 1
    check spec.exemptions["intent-gate"][0] == "rule-1"

# ---------------------------------------------------------------------------
# PolicyConfig instantiation
# ---------------------------------------------------------------------------

suite "PolicyConfig":
  test "can be constructed with valid data":
    let config = makeValidConfig()
    check $config.version == "1.0.0"
    check config.spec.rules.len == 1
    check config.loadedAt == "2026-06-18T00:00:00Z"
    check config.loadedFrom == "/etc/axiom/policy.json"

# ---------------------------------------------------------------------------
# validatePolicyRule
# ---------------------------------------------------------------------------

suite "validatePolicyRule":
  test "valid rule returns empty errors":
    let errors = validatePolicyRule(makeValidRule())
    check errors.len == 0

  test "empty id produces error":
    var rule = makeValidRule()
    rule.id = ""
    let errors = validatePolicyRule(rule)
    check errors.len == 1
    check "id must not be empty" in errors[0]

  test "empty description produces error":
    var rule = makeValidRule()
    rule.description = ""
    let errors = validatePolicyRule(rule)
    check errors.len == 1
    check "description must not be empty" in errors[0]

  test "empty deny and require produces error":
    var rule = makeValidRule()
    rule.deny = @[]
    rule.require = @[]
    let errors = validatePolicyRule(rule)
    check errors.len == 1
    check "must have at least one deny or require" in errors[0]

  test "deny-only rule is valid":
    var rule = makeValidRule()
    rule.require = @[]
    let errors = validatePolicyRule(rule)
    check errors.len == 0

  test "require-only rule is valid":
    var rule = makeValidRule()
    rule.deny = @[]
    let errors = validatePolicyRule(rule)
    check errors.len == 0

  test "multiple errors accumulate":
    var rule = makeValidRule()
    rule.id = ""
    rule.description = ""
    rule.deny = @[]
    rule.require = @[]
    let errors = validatePolicyRule(rule)
    check errors.len == 3

# ---------------------------------------------------------------------------
# validatePolicySpec
# ---------------------------------------------------------------------------

suite "validatePolicySpec":
  test "valid spec returns empty errors":
    let errors = validatePolicySpec(makeValidSpec())
    check errors.len == 0

  test "empty version produces error":
    var spec = makeValidSpec()
    spec.version = initPolicyVersion("")
    let errors = validatePolicySpec(spec)
    check errors.len >= 1
    var found = false
    for e in errors:
      if "version must not be empty" in e:
        found = true
    check found

  test "no rules produces error":
    var spec = makeValidSpec()
    spec.rules = @[]
    let errors = validatePolicySpec(spec)
    check errors.len >= 1
    var found = false
    for e in errors:
      if "must contain at least one rule" in e:
        found = true
    check found

  test "duplicate rule ids produce error":
    var spec = makeValidSpec()
    spec.rules = @[makeValidRule("dup", "first"), makeValidRule("dup", "second")]
    let errors = validatePolicySpec(spec)
    var found = false
    for e in errors:
      if "duplicate rule id" in e:
        found = true
    check found

  test "exemption referencing nonexistent rule produces error":
    var spec = makeValidSpec()
    spec.exemptions = {"gate-a": @["nonexistent-rule"]}.toTable
    let errors = validatePolicySpec(spec)
    var found = false
    for e in errors:
      if "does not match any rule" in e:
        found = true
    check found

  test "exemption referencing valid rule passes":
    var spec = makeValidSpec()
    spec.exemptions = {"gate-a": @["rule-1"]}.toTable
    let errors = validatePolicySpec(spec)
    check errors.len == 0

  test "invalid inner rules propagate errors":
    var spec = makeValidSpec()
    let badRule = PolicyRule(id: "", description: "", deny: @[], require: @[])
    spec.rules = @[badRule]
    let errors = validatePolicySpec(spec)
    check errors.len >= 2  # version + rule errors

# ---------------------------------------------------------------------------
# validatePolicyConfig
# ---------------------------------------------------------------------------

suite "validatePolicyConfig":
  test "valid config returns empty errors":
    let errors = validatePolicyConfig(makeValidConfig())
    check errors.len == 0

  test "empty version produces error":
    var config = makeValidConfig()
    config.version = initPolicyVersion("")
    let errors = validatePolicyConfig(config)
    var found = false
    for e in errors:
      if "PolicyConfig: version must not be empty" in e:
        found = true
    check found

  test "empty loadedAt produces error":
    var config = makeValidConfig()
    config.loadedAt = ""
    let errors = validatePolicyConfig(config)
    var found = false
    for e in errors:
      if "loadedAt must not be empty" in e:
        found = true
    check found

  test "empty loadedFrom produces error":
    var config = makeValidConfig()
    config.loadedFrom = ""
    let errors = validatePolicyConfig(config)
    var found = false
    for e in errors:
      if "loadedFrom must not be empty" in e:
        found = true
    check found

  test "spec errors are prefixed with PolicyConfig.spec:":
    var config = makeValidConfig()
    config.spec.rules = @[]
    let errors = validatePolicyConfig(config)
    var found = false
    for e in errors:
      if "PolicyConfig.spec:" in e:
        found = true
    check found

  test "multiple config-level errors accumulate":
    var config = makeValidConfig()
    config.version = initPolicyVersion("")
    config.loadedAt = ""
    config.loadedFrom = ""
    let errors = validatePolicyConfig(config)
    check errors.len >= 3
