import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}
# src/gate/cohesion_enforce.nim — Nim AST-based Cohesion Analysis
#
# Computes LCOM (Lack of Cohesion of Methods) and TCC (Tight Class Cohesion)
# using actual Nim AST node analysis, not FNV-1a hash strings.
#
# This replaces the deprecated cohesion_analyzer.nim which computed LCOM
# on cryptographic hash values (mathematically impossible).
#
# Uses `..<` range operator (Nim 2.2.10 confirmed stable).
# Phase 4: Wire to query_engine.nim solid-srp for pre-commit enforcement

{.push raises: [].}

import gate/architecture_ast_facts
import core/gate/architecture_policy
import gate/rule_patterns
import std/tables

type
  CohesionResult* = object
    modulePath*: string
    lcom*: float
    tcc*: float
    functionCount*: int
    passes*: bool

func computeCohesion*(functions: seq[(string, seq[string])]): CohesionResult {.raises: [].} =
  ## Compute LCOM and TCC from function identifier sets.
  ##
  ## LCOM = (pairs with no shared identifiers) / (total pairs)
  ## TCC  = (pairs with shared identifiers) / (total pairs)
  ##
  ## Lower LCOM → higher cohesion (good)
  ## Higher TCC  → higher cohesion (good)

  if functions.len < 2:
    return CohesionResult(lcom: 0.0, tcc: 1.0, functionCount: functions.len, passes: true)

  var connectedPairs = 0
  var totalPairs = 0

  for i in 0 ..< functions.len:
    for j in (i + 1) ..< functions.len:
      inc totalPairs
      let (_, refsA) = functions[i]
      let (_, refsB) = functions[j]
      var hasShared = false
      for refA in refsA:
        if refA in refsB:
          hasShared = true
          break
      if hasShared:
        inc connectedPairs


  let lcom = 1.0 - (connectedPairs.float / totalPairs.float)
  let tcc = connectedPairs.float / totalPairs.float

  result = CohesionResult(
    modulePath: "",
    lcom: lcom,
    tcc: tcc,
    functionCount: functions.len,
    passes: true)

func checkCohesionV2*(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## Check SRP violation via LCOM/TCC cohesion metrics (AST-based).
  ##
  ## Iterates modules, builds (name, bodyTokens) pairs from each module's
  ## functions' normalized AST fingerprints, computes LCOM/TCC, and flags
  ## violations when policy thresholds are exceeded.
  ##
  ## This replaces the deprecated hash-based checkCohesion from cohesion_analyzer.nim.

  for moduleFacts in allFacts:
    var functionsData: seq[(string, seq[string])] = @[]
    for fn in moduleFacts.functions:
      # Use real nkIdent references from v3 extractor (PNode-based).
      # Fallback to fingerprint for legacy/compat.
      let refs = if fn.variableRefs.len > 0: fn.variableRefs
                 else: @[fn.normalizedAstFingerprint]
      functionsData.add((fn.name, refs))

    let cohesion = computeCohesion(functionsData)
    # Check per-module LCOM override first, fall back to global threshold
    var maxLcom = policy.cohesion.maxLcom
    try:
      if policy.cohesion.lcomOverrides.hasKey(moduleFacts.path):
        maxLcom = policy.cohesion.lcomOverrides[moduleFacts.path]
    except KeyError:
      discard
    # Check per-module TCC override first, fall back to global threshold
    var minTcc = policy.cohesion.minTcc
    try:
      if policy.cohesion.tccOverrides.hasKey(moduleFacts.path):
        minTcc = policy.cohesion.tccOverrides[moduleFacts.path]
    except KeyError:
      discard
    var detail = ""

    if maxLcom > 0.0 and cohesion.lcom > maxLcom:
      detail = moduleFacts.path & ": LCOM=" & $cohesion.lcom &
        " exceeds threshold " & $maxLcom &
        " (low cohesion — SRP violation)"
    elif minTcc > 0.0 and cohesion.tcc < minTcc:
      detail = moduleFacts.path & ": TCC=" & $cohesion.tcc &
        " below threshold " & $minTcc &
        " (low cohesion — SRP violation)"

    if detail.len > 0:
      result.add(ArchitectureViolationArtifact(
        rule: "SOLID",
        detail: detail,
        files: @[moduleFacts.path],
        severity: "warning"))

{.pop.}
{.pop.}
