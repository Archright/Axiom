## tests/unit/test_policy_layer_structure.nim
##
## Compile-time deterministic validation of canonical Contract/Policy Layer
## JSONC artifacts. No filesystem access at runtime; staticRead + parseJson.
## SSOT: docs/spec/canonical_contract_policy_layer.md

import std/[unittest, json, strutils]

# ── Static reads (compile-time) ──────────────────────────────────────

const PolicyDispositionsJsonc* = staticRead("config/policy/policy_dispositions.json")
const BudgetsJsonc*          = staticRead("data/debt_budgets.json")
const ContractSchemaJsonc*   = staticRead("config/policy/contract_layer.schema.json")
const PolicySchemaJsonc*     = staticRead("config/policy/policy_layer.schema.json")
const ExampleBudgetDriftJsonc* = staticRead("config/policy/examples_budget_drift_info.json")
const ExampleAllowlistJsonc*   = staticRead("config/policy/examples_allowlist_anchor.json")
const ExampleEvidenceJsonc*    = staticRead("config/policy/examples_evidence_envelope.json")

# ── JSONC comment stripper (string-aware, from tools/debt_engine.nim) ─

func stripJsonComments(jsonc: string): string {.raises: [].} =
  ## Removes // line comments and /* */ block comments, preserving string
  ## contents (including URLs with //). Does NOT strip inside literals.
  var buf = newStringOfCap(jsonc.len)
  var i = 0
  var inString = false
  var inBlockComment = false
  var escapeNext = false
  while i < jsonc.len:
    let ch = jsonc[i]
    let nextCh = if i + 1 < jsonc.len: jsonc[i + 1] else: '\0'
    if inBlockComment:
      if ch == '*' and nextCh == '/':
        inBlockComment = false
        inc i
    elif inString:
      buf.add(ch)
      if escapeNext:
        escapeNext = false
      elif ch == '\\':
        escapeNext = true
      elif ch == '"':
        inString = false
    else:
      if ch == '"':
        inString = true
        buf.add(ch)
      elif ch == '/' and nextCh == '/':
        inc i
        while i < jsonc.len and jsonc[i] != '\n':
          inc i
      elif ch == '/' and nextCh == '*':
        inBlockComment = true
        inc i
      else:
        buf.add(ch)
    inc i
  return buf

# ══════════════════════════════════════════════════════════════════════
# Test Suite
# ══════════════════════════════════════════════════════════════════════

suite "policy layer structure":

  test "all 6 JSONC artifacts parse successfully":
    # Every artifact must yield a non-null JsonNode after stripping // comments.
    let d = parseJson(stripJsonComments(PolicyDispositionsJsonc))
    let b = parseJson(stripJsonComments(BudgetsJsonc))
    let cs = parseJson(stripJsonComments(ContractSchemaJsonc))
    let ps = parseJson(stripJsonComments(PolicySchemaJsonc))
    let eb = parseJson(stripJsonComments(ExampleBudgetDriftJsonc))
    let ea = parseJson(stripJsonComments(ExampleAllowlistJsonc))
    let ev = parseJson(stripJsonComments(ExampleEvidenceJsonc))
    check d.kind != JNull
    check b.kind != JNull
    check cs.kind != JNull
    check ps.kind != JNull
    check eb.kind != JNull
    check ea.kind != JNull
    check ev.kind != JNull

  test "policy_dispositions covers every budget metric with no extras":
    let b = parseJson(stripJsonComments(BudgetsJsonc))
    let d = parseJson(stripJsonComments(PolicyDispositionsJsonc))
    # Every budget metric must have a disposition entry; no extra entries.
    var budgetKeyCount = 0
    for k, _ in b["metrics"].pairs:
      inc budgetKeyCount
      check d["metrics"].hasKey(k)
    var dispKeyCount = 0
    for k, _ in d["metrics"].pairs:
      inc dispKeyCount
      check b["metrics"].hasKey(k)
    check budgetKeyCount == dispKeyCount

  test "every disposition value is a valid contract disposition (INFO|WARN|ERROR)":
    # ERROR is a contract-valid disposition — escalation to hard-fail works by
    # editing the artifact to ERROR, so the test must accept it (never rebind
    # the escalation mechanism), and must reject unknown/malformed values.
    let d = parseJson(stripJsonComments(PolicyDispositionsJsonc))
    let validDispositions = @["INFO", "WARN", "ERROR"]
    for _, val in d["metrics"].pairs:
      let disp = val["disposition"].getStr()
      check disp in validDispositions

  test "contract_layer.schema carries all required top-level keys":
    # Spec §2: $schema, $comment, title, description, definitions, allOf
    let cs = parseJson(stripJsonComments(ContractSchemaJsonc))
    let requiredContract = @["$schema", "$comment", "title", "description", "definitions", "allOf"]
    for k in requiredContract:
      check cs.hasKey(k)

  test "policy_layer.schema carries all required top-level keys":
    # Spec §3: $schema, $comment, title, description, definitions, allOf
    let ps = parseJson(stripJsonComments(PolicySchemaJsonc))
    let requiredPolicy = @["$schema", "$comment", "title", "description", "definitions", "allOf"]
    for k in requiredPolicy:
      check ps.hasKey(k)

  test "examples_budget_drift_info has metricResult DRIFT and disposition INFO":
    # Evaluator decides PASS|DRIFT; policy assigns INFO severity (non-blocking).
    let eb = parseJson(stripJsonComments(ExampleBudgetDriftJsonc))
    check eb["observation"]["result"].getStr() == "DRIFT"
    check eb["decision"]["disposition"].getStr() == "INFO"

  test "examples_allowlist_anchor uses path+symbol+kind as identity (no line-as-identity)":
    # Anchor contract: identity = path + symbol + semanticKind.
    # Line numbers MUST NOT appear at the anchor top level; if present,
    # they belong under derivedEvidence only.
    let ea = parseJson(stripJsonComments(ExampleAllowlistJsonc))
    let anchor = ea["anchor"]
    check anchor.hasKey("path")
    check anchor.hasKey("symbol")
    check anchor.hasKey("semanticKind")
    check anchor["path"].getStr().len > 0
    check anchor["symbol"].getStr().len > 0
    check anchor["semanticKind"].getStr().len > 0
    # No bare 'line' key at anchor top level
    check not anchor.hasKey("line")

  test "examples_evidence_envelope parses and has envelopeId":
    let ev = parseJson(stripJsonComments(ExampleEvidenceJsonc))
    check ev.hasKey("evidenceEnvelope")
    check ev["evidenceEnvelope"].hasKey("envelopeId")
    check ev["evidenceEnvelope"]["envelopeId"].getStr().len > 0
