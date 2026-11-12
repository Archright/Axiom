## selection-digest-compare — S2 Parity Gate Comparator
##
## Reads two selection reports (e.g., one local, one CI) and compares
## them gate-by-gate in order:
##   ① semanticInputIdentity must be byte-equal
##   ② selection.derivationDigest / status must be equal
##   ③ plan.planDigest must be equal
##   ④ resultComparison is recorded as "deferred-until-execution"
##     (execution results are checked by the S4 projection golden gate).
##
## Usage:
##   selection-digest-compare <reportA.json> <reportB.json>
##
## Exit codes:
##   0 — all gates ①–③ pass
##   1 — gate failure (identifies which gate and field)

import std/[os, json, strutils, strformat, sequtils, algorithm]

# ═══════════════════════════════════════════════════════════════════════════
# §1: Types
# ═══════════════════════════════════════════════════════════════════════════

type
  GateResult* = enum
    grPass
    grFail
    grMissing

  GateReport* = object
    gate*: string
    result*: GateResult
    detail*: string

# ═══════════════════════════════════════════════════════════════════════════
# §2: Gate implementations (pure logic where possible)
# ═══════════════════════════════════════════════════════════════════════════

proc checkSemanticInputIdentity*(a, b: JsonNode): GateReport =
  ## Gate ①: semanticInputIdentity must be byte-equal (all fields match).
  let aIdentity = a{"semanticInputIdentity"}
  let bIdentity = b{"semanticInputIdentity"}

  if aIdentity == nil or bIdentity == nil:
    return GateReport(gate: "① semanticInputIdentity", result: grMissing,
      detail: "One or both reports missing semanticInputIdentity section")

  let aStr = $aIdentity
  let bStr = $bIdentity
  if aStr == bStr:
    GateReport(gate: "① semanticInputIdentity", result: grPass, detail: "")
  else:
    # Identify which field differs
    var diffFields: seq[string]
    for key in @["changeSetDigest", "graphDigest", "universeDigest", "policyDigest"]:
      if aIdentity.hasKey(key) and bIdentity.hasKey(key):
        if aIdentity[key].getStr() != bIdentity[key].getStr():
          diffFields.add(key)
      elif aIdentity.hasKey(key) xor bIdentity.hasKey(key):
        diffFields.add(key & " (missing in one report)")

    let detail = if diffFields.len > 0:
      "Fields differ: " & diffFields.join(", ")
    else:
      "semanticInputIdentity content differs (structure or values)"

    GateReport(gate: "① semanticInputIdentity", result: grFail, detail: detail)

proc checkSelectionDerivation*(a, b: JsonNode): GateReport =
  ## Gate ②: selection.derivationDigest and status must be equal.
  let aSel = a{"selection"}
  let bSel = b{"selection"}

  if aSel == nil or bSel == nil:
    return GateReport(gate: "② selection.derivationDigest/status", result: grMissing,
      detail: "One or both reports missing selection section")

  var failures: seq[string]

  # Check status
  let aStatus = aSel{"status"}.getStr("")
  let bStatus = bSel{"status"}.getStr("")
  if aStatus != bStatus:
    failures.add(&"status: '{aStatus}' vs '{bStatus}'")

  # Check derivationDigest
  let aDeriv = aSel{"derivationDigest"}.getStr("")
  let bDeriv = bSel{"derivationDigest"}.getStr("")
  if aDeriv != bDeriv:
    failures.add(&"derivationDigest differs")

  if failures.len == 0:
    GateReport(gate: "② selection.derivationDigest/status", result: grPass, detail: "")
  else:
    GateReport(gate: "② selection.derivationDigest/status", result: grFail,
      detail: failures.join("; "))

proc checkPlanDigest*(a, b: JsonNode): GateReport =
  ## Gate ③: plan.planDigest must be equal.
  let aPlan = a{"plan"}
  let bPlan = b{"plan"}

  if aPlan == nil or bPlan == nil:
    return GateReport(gate: "③ plan.planDigest", result: grMissing,
      detail: "One or both reports missing plan section")

  let aDigest = aPlan{"planDigest"}.getStr("")
  let bDigest = bPlan{"planDigest"}.getStr("")

  if aDigest == bDigest:
    GateReport(gate: "③ plan.planDigest", result: grPass, detail: "")
  else:
    GateReport(gate: "③ plan.planDigest", result: grFail,
      detail: &"planDigest: '{aDigest}' vs '{bDigest}'")

proc buildResultComparison*(a, b: JsonNode): JsonNode =
  ## Gate ④: record resultComparison as deferred-until-execution.
  ## Execution results are checked by the S4 projection golden gate,
  ## not by this tool. This gate is always "deferred" because the
  ## comparator only checks digests ①–③.
  %*{
    "resultComparison": "deferred-until-execution",
    "note": "Execution result equality (gate ④) is checked by the S4 projection golden gate, not by this comparator. This tool compares only the first three semantic-input gates.",
    "gatesChecked": ["① semanticInputIdentity", "② selection.derivationDigest/status", "③ plan.planDigest"],
    "gate4Deferred": "resultComparison deferred to S4 projection golden gate"}

# ═══════════════════════════════════════════════════════════════════════════
# §3: Report loading
# ═══════════════════════════════════════════════════════════════════════════

proc loadReport*(path: string): JsonNode =
  ## Load a selection report JSON from disk.
  if not fileExists(path):
    echo &"[selection-digest-compare] ERROR: report not found: {path}"
    quit(1)

  try:
    let content = readFile(path)
    result = parseJson(content)
  except CatchableError as e:
    echo &"[selection-digest-compare] ERROR: failed to parse {path}: {e.msg}"
    quit(1)

# ═══════════════════════════════════════════════════════════════════════════
# §4: Main
# ═══════════════════════════════════════════════════════════════════════════

proc main() =
  if commandLineParams().len < 2:
    echo "Usage: selection-digest-compare <reportA.json> <reportB.json>"
    echo ""
    echo "Compares two selection reports gate-by-gate:"
    echo "  ① semanticInputIdentity (byte-equal)"
    echo "  ② selection.derivationDigest / status (equal)"
    echo "  ③ plan.planDigest (equal)"
    echo "  ④ resultComparison: deferred-until-execution"
    echo ""
    echo "Exit: 0 = all gates pass, 1 = gate failure"
    quit(1)

  let pathA = commandLineParams()[0]
  let pathB = commandLineParams()[1]

  let reportA = loadReport(pathA)
  let reportB = loadReport(pathB)

  # Run gates in order
  let gate1 = checkSemanticInputIdentity(reportA, reportB)
  let gate2 = checkSelectionDerivation(reportA, reportB)
  let gate3 = checkPlanDigest(reportA, reportB)
  let gate4 = buildResultComparison(reportA, reportB)

  # Collect results
  let gates = @[gate1, gate2, gate3]
  let allPass = gates.allIt(it.result == grPass)

  # Build output
  var output = %*{
    "gate1_semanticInputIdentity": %*{
      "result": $gate1.result,
      "detail": gate1.detail},
    "gate2_selectionDerivation": %*{
      "result": $gate2.result,
      "detail": gate2.detail},
    "gate3_planDigest": %*{
      "result": $gate3.result,
      "detail": gate3.detail},
    "gate4_resultComparison": gate4}

  # Write to stdout
  echo pretty(output, 2)

  if allPass:
    quit(0)
  else:
    # Identify the first failing gate
    for g in gates:
      if g.result == grFail:
        echo &"[selection-digest-compare] FAIL: {g.gate} — {g.detail}"
    quit(1)

when isMainModule:
  main()