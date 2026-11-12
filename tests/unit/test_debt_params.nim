## Unit tests for core/utils/debt_params — parseDebtParams & formatDebtParams
## Business-scenario only (AGENTS.md §0.7). No compiler-guaranteed behavior tested.
##
## Run: nim c --hints:off --path:src -r tests/unit/test_debt_params.nim

import std/unittest
import std/tables
import core/utils/debt_params

suite "new macro syntax — axiomDebt(...)":
  test "parses id, ttl, severity, category":
    let p = parseDebtParams(
      """axiomDebt("DEBT#243", ttl="2026-07-15", severity="high", category="structural")"""
    )
    check p.valid
    check p.id == "DEBT#243"
    check p.ttl == "2026-07-15"
    check p.severity == sevHigh
    check p.category == "structural"

  test "parses only id — remaining fields at defaults":
    let p = parseDebtParams("""axiomDebt("DEBT#1")""")
    check p.valid
    check p.id == "DEBT#1"
    check p.ttl == ""
    check p.severity == sevMedium   # default
    check p.category == ""

  test "extra key-value goes into extra table":
    let p = parseDebtParams(
      """axiomDebt("DEBT#9", verifies="some_spec")"""
    )
    check p.valid
    check p.id == "DEBT#9"
    check p.extra["verifies"] == "some_spec"

suite "old pragma syntax — {.axiomDebt: ...}":
  test "parses id and category":
    let p = parseDebtParams(
      """{.axiomDebt: "DEBT#243", category: "structural".}"""
    )
    check p.valid
    check p.id == "DEBT#243"
    check p.category == "structural"

  test "parses only id in pragma":
    let p = parseDebtParams("""{.axiomDebt: "DEBT#50".}""")
    check p.valid
    check p.id == "DEBT#50"
    check p.category == ""

suite "severity enum mapping":
  test "sevLow":
    check parseSeverity("low") == sevLow

  test "sevMedium":
    check parseSeverity("medium") == sevMedium

  test "sevHigh":
    check parseSeverity("high") == sevHigh

  test "sevCritical":
    check parseSeverity("critical") == sevCritical

  test "case-insensitive":
    check parseSeverity("HIGH") == sevHigh
    check parseSeverity("Critical") == sevCritical

suite "unknown severity defaults to sevMedium":
  test "unknown string":
    check parseSeverity("banana") == sevMedium

  test "empty string":
    check parseSeverity("") == sevMedium

suite "empty / invalid input returns valid=false":
  test "empty string":
    let p = parseDebtParams("")
    check not p.valid

  test "unrelated text":
    let p = parseDebtParams("nim c -r main.nim")
    check not p.valid

  test "axiomDebt keyword without macro call or pragma":
    let p = parseDebtParams("axiomDebt is used for debt tracking")
    check not p.valid

  test "malformed pragma — missing closing .}":
    let p = parseDebtParams("""{.axiomDebt: "DEBT#1", category: "x"""")
    check not p.valid

  test "malformed macro — missing closing paren":
    let p = parseDebtParams("""axiomDebt("DEBT#1", category="x")""")
    # This one actually has the closing paren, so it should parse fine.
    # Use a truly broken string instead:
    let p2 = parseDebtParams("""axiomDebt("DEBT#1", category="x" """)
    check not p2.valid

suite "formatDebtParams":
  test "full params":
    var p = DebtParams(
      id: "DEBT#243",
      ttl: "2026-07-15",
      severity: sevHigh,
      category: "structural",
      valid: true
    )
    check formatDebtParams(p) == "DEBT#243, ttl=2026-07-15, severity=high, category=structural"

  test "no ttl, no category":
    let p = DebtParams(id: "DEBT#1", severity: sevMedium, valid: true)
    check formatDebtParams(p) == "DEBT#1, severity=medium"

  test "critical severity":
    let p = DebtParams(id: "DEBT#99", severity: sevCritical, valid: true)
    check formatDebtParams(p) == "DEBT#99, severity=critical"

suite "round-trip parse → format":
  test "new macro syntax round-trip":
    let input = """axiomDebt("DEBT#7", ttl="2026-09-01", severity="low", category="doc")"""
    let p = parseDebtParams(input)
    check p.valid
    let formatted = formatDebtParams(p)
    check formatted == "DEBT#7, ttl=2026-09-01, severity=low, category=doc"
