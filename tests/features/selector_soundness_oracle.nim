## P8.1 Selector Soundness — mutation catalog oracle consistency test.
##
## Independently re-derives and validates the mutation catalog:
##   data/selector_soundness/mutation_catalog.json
##
## The oracle checks catalog internal consistency (unique ids, valid class,
## classificationState == "classified", well-formed expectedAffected within
## {W1..W11} — with ∅ (empty) now a LEGAL case per the approved plan ADR
## 개정 "오라클 스키마 ∅ 허용" (a docs-only mutation may legitimately affect
## no work unit; the selector's mode=none floor regression depends on this) —
## non-empty derivation).  Any contamination (invalid class, or a
## record whose classificationState is not "classified") MUST fail — this is
## the oracle catching catalog contamination that would otherwise silently
## weaken the P4 soundness gate.
##
## AGENTS.md §0.7: Business-Only Test Scope.

import std/json
import std/os
import std/strutils
import std/sets
import std/tables
import gate/proof_unit_catalog

const
  CatalogPath = "data" / "selector_soundness" / "mutation_catalog.json"
  ValidClasses = ["implementation", "dependency-edge", "generated-artifact",
                  "contract-document", "build-config"]
  ## W ids sourced from the single editing authority
  ## (src/gate/proof_unit_catalog.nim) — never hardcoded here.
  ValidWorkUnits = block:
    var ids: seq[string]
    for u in ProofUnitCatalog:
      ids.add(u.id)
    ids
  ClassifiedState = "classified"

proc findRepoRoot(): string =
  ## Walk upward from CWD to find .axiom_root (mirrors the selector's logic).
  var dir = getCurrentDir()
  for _ in 0 ..< 10:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  # Fall back to CWD so the test still runs when launched from repo root.
  getCurrentDir()

proc run() =
  var passed = 0
  var failed = 0

  template check(name: string, cond: bool) =
    if cond:
      inc passed
      echo "  PASS: " & name
    else:
      inc failed
      echo "  FAIL: " & name

  let repoRoot = findRepoRoot()
  let catalogFile = repoRoot / CatalogPath
  check "catalog exists at " & catalogFile, fileExists(catalogFile)
  if not fileExists(catalogFile):
    echo "FATAL: catalog not found; cannot continue."
    quit(1)

  let data = catalogFile.parseFile()
  check "catalog is a JSON array", data.kind == JArray

  if data.kind != JArray:
    echo "FATAL: catalog root is not an array."
    quit(1)

  var seenIds = initHashSet[string]()
  var seenWorkUnits = initHashSet[string]()
  for wu in ValidWorkUnits:
    seenWorkUnits.incl(wu)

  var classCounts = initCountTable[string]()
  var i = 0
  for rec in data:
    i += 1
    let prefix = "record[" & $i & "]"

    # id present and unique
    let id = rec{"id"}.getStr("")
    check prefix & " has non-empty id", id.len > 0
    check prefix & " id unique (" & id & ")", id notin seenIds
    seenIds.incl(id)

    # class must be one of the 5-value ontology
    let cls = rec{"class"}.getStr("")
    check prefix & " class in 5-value ontology (" & cls & ")",
          cls in ValidClasses
    classCounts.inc(cls)

    # classificationState must be "classified"; anything else is contamination
    let cs = rec{"classificationState"}.getStr("")
    check prefix & " classificationState == classified (" & cs & ")",
          cs == ClassifiedState

    # triggerFile non-empty
    let trigger = rec{"triggerFile"}.getStr("")
    check prefix & " has non-empty triggerFile", trigger.len > 0

    # expectedAffected: array; entries each ∈ {W1..W11} when present. ∅ is a
    # LEGAL case per the approved plan ADR 개정 "오라클 스키마 ∅ 허용" (docs-only
    # mutations may legitimately affect no work unit — the selector's mode=none
    # floor regression test tests/ci/test_oracle_evidence_regression.nim depends
    # on this). The former empty-forbidden check is removed by that 개정 —
    # soundness of every other judgment is unchanged.
    let exp = rec{"expectedAffected"}
    check prefix & " expectedAffected is array", exp.kind == JArray
    if exp.kind == JArray:
      for wu in exp:
        let idstr = wu.getStr("")
        check prefix & " expectedAffected entry in {W1..W11} (" & idstr & ")",
              idstr in seenWorkUnits

    # derivation non-empty
    let deriv = rec{"expectedAffectedDerivation"}.getStr("")
    check prefix & " has non-empty expectedAffectedDerivation", deriv.len > 0

    # declaredOracleRef ∈ {catalog, makefile-target}
    let oracleRef = rec{"declaredOracleRef"}.getStr("")
    check prefix & " declaredOracleRef in {catalog, makefile-target} (" & oracleRef & ")",
          oracleRef == "catalog" or oracleRef == "makefile-target"

  # All 5 classes must be covered (P4 completion condition 1)
  for c in ValidClasses:
    check "class covered: " & c, classCounts.hasKey(c)

  echo ""
  echo "Oracle results: $# passed, $# failed" % [$passed, $failed]
  if failed == 0:
    echo "EXIT 0: catalog is internally consistent; no contamination."
    quit(0)
  else:
    echo "EXIT 1: catalog oracle FAILED — P4 must not pass."
    quit(1)

when isMainModule:
  run()
