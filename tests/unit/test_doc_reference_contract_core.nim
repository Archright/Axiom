## tests/unit/test_doc_reference_contract_core.nim
##
## Tier-1 regression: the PURE reference-resolution core of the document
## reference contract (docs/spec/document_reference_contract.md) —
## `tools/ci/doc_path_validator_core.nim`.
##
## This test exercises the decision logic in isolation with a MOCK `TargetProbe`
## value. It performs NO filesystem access and NO `make` subprocess, so every
## scenario (S1..S8) is deterministic regardless of the workspace Makefile or
## locale. The real `make -n` adapter is covered by its own integration test
## (test_make_probe_integration.nim). Locking the contract (INVARIANT-DRP-7):
## the only ways a missing target avoids FAIL are HISTORICAL_ALLOWED,
## GENERATED_ALLOWED with an EXISTS reproducer, or EXTERNAL_ALLOWED.

import std/[unittest, options, tables]

import ci/doc_path_validator_core

# ═══════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════

proc cfgOf(raw: string): ReferencePolicyConfig =
  ## Parse a policy-manifest snippet via the PURE parser (no I/O).
  parseReferencePolicyConfig(raw)

let noMatcherPath = "docs/audit/nonexistent.json"

# ═══════════════════════════════════════════════════════════════════════
# Suite — resolver scenarios
# ═══════════════════════════════════════════════════════════════════════

suite "doc reference contract — resolver (pure)":
  test "S1 unclassified/MUST_EXIST target missing → FAIL (fail-closed default)":
    let cfg = cfgOf("{}")   # empty manifest → every path defaults to MUST_EXIST
    let entry = referencePolicyFor(cfg, noMatcherPath)
    check entry.policy == rpMustExist
    let (allowed, reason) = resolveReferencePolicy(entry, tpProbeError)
    check allowed == false
    check reason == rrMustExistFailed

  test "S2 HISTORICAL_ALLOWED target missing → PASS (not a finding)":
    let cfg = cfgOf(
      """{"docs/audit/nonexistent.json":{"policy":"HISTORICAL_ALLOWED"}}""")
    let entry = referencePolicyFor(cfg, noMatcherPath)
    check entry.policy == rpHistoricalAllowed
    # probe value is irrelevant for non-generated policies
    let (allowed, reason) = resolveReferencePolicy(entry, tpProbeError)
    check allowed == true
    check reason == rrOk

  test "S3 GENERATED_ALLOWED missing + EXISTS reproducer → PASS":
    let cfg = cfgOf(
      """{"docs/audit/nonexistent.json":{"policy":"GENERATED_ALLOWED","reproducerTarget":"make audit-dir-doc"}}""")
    let entry = referencePolicyFor(cfg, noMatcherPath)
    check entry.policy == rpGeneratedAllowed
    check entry.reproducerTarget == "make audit-dir-doc"
    let (allowed, reason) = resolveReferencePolicy(entry, tpExists)
    check allowed == true
    check reason == rrOk

  test "S4 GENERATED_ALLOWED missing + NO reproducer → FAIL (rrGeneratedNoReproducer)":
    let cfg = cfgOf(
      """{"docs/audit/nonexistent.json":{"policy":"GENERATED_ALLOWED"}}""")
    let entry = referencePolicyFor(cfg, noMatcherPath)
    check entry.policy == rpGeneratedAllowed
    check entry.reproducerTarget == ""
    let (allowed, reason) = resolveReferencePolicy(entry, tpExists)
    check allowed == false
    check reason == rrGeneratedNoReproducer

  test "S6 GENERATED_ALLOWED reproducer tri-state: ABSENT → FAIL, PROBE-ERROR → FAIL":
    let cfg = cfgOf(
      """{"docs/audit/nonexistent.json":{"policy":"GENERATED_ALLOWED","reproducerTarget":"make audit-dir-doc"}}""")
    let entry = referencePolicyFor(cfg, noMatcherPath)
    let (aAbsent, rAbsent) = resolveReferencePolicy(entry, tpAbsent)
    check aAbsent == false
    check rAbsent == rrTargetAbsent
    let (aErr, rErr) = resolveReferencePolicy(entry, tpProbeError)
    check aErr == false
    check rErr == rrProbeError   # fail-closed: never promoted to allowed

  test "EXTERNAL_ALLOWED missing → PASS (never durable truth)":
    let cfg = cfgOf(
      """{"docs/audit/nonexistent.json":{"policy":"EXTERNAL_ALLOWED"}}""")
    let entry = referencePolicyFor(cfg, noMatcherPath)
    check entry.policy == rpExternalAllowed
    let (allowed, reason) = resolveReferencePolicy(entry, tpProbeError)
    check allowed == true
    check reason == rrOk

  test "referencePolicyFor defaults unknown path to MUST_EXIST":
    let cfg = cfgOf(
      """{"only/other.json":{"policy":"HISTORICAL_ALLOWED"}}""")
    let entry = referencePolicyFor(cfg, noMatcherPath)
    check entry.policy == rpMustExist

  test "reasonText is display-only and total over all ResolveReason values":
    for r in [rrOk, rrMustExistFailed, rrGeneratedNoReproducer, rrTargetAbsent,
              rrProbeError, rrMalformedPolicy, rrUnusedPolicy]:
      check reasonText(r).len > 0

suite "doc reference contract — manifest parser (pure)":
  test "S5 malformed JSON → malformed config (fail-closed)":
    let cfg = cfgOf("""{"docs/audit/nonexistent.json": {""")  # truncated object
    check cfg.malformed == true
    check cfg.malformedReason.len > 0

  test "S5 unknown policy value → malformed":
    let cfg = cfgOf(
      """{"docs/audit/x.json":{"policy":"MAYBE_ALLOWED"}}""")
    check cfg.malformed == true

  test "S5 unknown per-entry field (semantic authority) → malformed":
    let cfg = cfgOf(
      """{"docs/audit/x.json":{"policy":"HISTORICAL_ALLOWED","authority":"derived"}}""")
    check cfg.malformed == true

  test "comment field is permitted and ignored":
    let cfg = cfgOf(
      """{"docs/audit/x.json":{"policy":"HISTORICAL_ALLOWED","comment":"doc only"}}""")
    check cfg.malformed == false
    let entry = referencePolicyFor(cfg, "docs/audit/x.json")
    check entry.policy == rpHistoricalAllowed

  test "GENERATED_ALLOWED without reproducer is NOT malformed (resolver-FAIL, not parse-FAIL)":
    let cfg = cfgOf(
      """{"docs/audit/x.json":{"policy":"GENERATED_ALLOWED"}}""")
    check cfg.malformed == false   # precise rrGeneratedNoReproducer at resolve time

# ═══════════════════════════════════════════════════════════════════════
# Suite — path canonicalization + unused-entry detection (S8)
# ═══════════════════════════════════════════════════════════════════════

suite "doc reference contract — canonicalization + S8 (pure)":
  test "canonicalizePath normalizes case, backslash, duplicate/trailing slash, ./ and ..":
    check canonicalizePath("Docs/Audit/Report.JSON") == "docs/audit/report.json"
    check canonicalizePath(r"docs\audit\report.json") == "docs/audit/report.json"
    check canonicalizePath("docs//audit/./report.json") == "docs/audit/report.json"
    check canonicalizePath("docs/audit/report.json/") == "docs/audit/report.json"
    check canonicalizePath("./docs/audit/report.json") == "docs/audit/report.json"
    check canonicalizePath("docs/a/../audit/report.json") == "docs/audit/report.json"
    check canonicalizePath("Docs/Audit/Report.json") ==
          canonicalizePath("docs/audit/report.json")

  test "S8a live policy entry (referenced) is NOT unused → no finding":
    let cfg = cfgOf(
      """{"docs/audit/nonexistent.json":{"policy":"HISTORICAL_ALLOWED"}}""")
    let referenced = @[noMatcherPath]
    check findUnusedPolicyEntries(cfg, referenced).len == 0

  test "S8b dead policy entry (never referenced) IS unused → finding":
    let cfg = cfgOf(
      """{"docs/audit/a.json":{"policy":"HISTORICAL_ALLOWED"},
          "docs/audit/orphan.json":{"policy":"EXTERNAL_ALLOWED"}}""")
    # only a.json is referenced
    let referenced = @["docs/audit/a.json"]
    let unused = findUnusedPolicyEntries(cfg, referenced)
    check unused.len == 1
    check unused[0] == "docs/audit/orphan.json"

  test "S8 match is canonical (case/slash-insensitive) — no false unused":
    let cfg = cfgOf(
      """{"Docs/Audit/Report.json":{"policy":"HISTORICAL_ALLOWED"}}""")
    # referenced with different case/slash shape but same canonical path
    let referenced = @[r"docs\audit\report.json"]
    check findUnusedPolicyEntries(cfg, referenced).len == 0
