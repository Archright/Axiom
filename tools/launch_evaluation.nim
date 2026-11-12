## tools/launch_evaluation.nim — deterministic, dependency-free launch-evaluation projection.
##
## DERIVES data/readiness/launch_evaluation.json from three existing inputs:
##   - data/readiness/launch_requirements.json    (Productization Entry Contract v1 registry)
##   - data/readiness/decision.independent.<UTC>.json  (per-invariant readiness states; latest)
##   - data/readiness/closure_state.json          (per-blocker closure lifecycle)
##
## It is a PURE PROJECTION over the readiness evaluator's existing decision artifact — it does
## NOT re-evaluate invariants, does NOT mutate the evaluator (data/readiness/evaluate.py,
## tools/readiness_evaluator.nim), the decision artifact, the policy, or the closure records.
## It respects docs/spec/continual_revalidation.md:95 ("do not add another projection engine /
## keep the readiness evaluator as SSOT"): this is a deterministic downstream derivation, not a
## competing verdict source.
##
## VERDICT MODEL (v1, ratified): binary GO/NO-GO. GO iff every launch requirement is satisfied,
## else NO-GO. CONDITIONAL is explicitly OUT of v1 scope.
##
## PREDICATE VOCABULARY (fixed, machine-evaluable — no arbitrary expressions):
##   EVIDENCE_ALL_SATISFIED: satisfied iff EVERY requiredEvidence resolves to a decision state of "PASS".
##   EVIDENCE_ANY_SATISFIED : satisfied iff ANY requiredEvidence resolves to "PASS".   (defined, unused in v1)
##   NO_BLOCKER_IN_REQUIRED_SET: satisfied iff none of requiredEvidence resolves to "FAIL". (defined, unused)
##
## EVIDENCE RESOLUTION: a requiredEvidence id is either a plain invariant (e.g. "R4") or a suffixed
## sub-slice (e.g. "R8-P"). The decision artifact only carries parent invariants ("R8"), so a
## suffixed id resolves to its parent invariant (strip the "-<suffix>").
##
## Test scope: this slice makes NO evaluator edit, NO policy-criticality change. Deterministic:
## no timestamps in output, no random, no network. Paths resolve relative to the repo root.
##
## Exit: 0 = evaluation produced (and written); non-zero = could not produce (missing inputs, etc.).

import std/[json, os, strutils, tables, sequtils]

type
  Requirement = object
    name: string
    evidence: seq[string]
    predicate: string
    closureState: string
    status: string  ## "REQUIRED" (Launch-Critical) | "HARDENING" (Integrity-Hardening), derived from Entry Contract §2 status.

proc parentInvariant(s: string): string =
  ## Resolve a (possibly suffixed) evidence id to its parent invariant id.
  let dash = s.find('-')
  if dash > 0: s[0 ..< dash] else: s

proc repoRoot(): string =
  var dir = getAppDir()
  for _ in 0 .. 3:
    if fileExists(dir / "config.nims"):
      return dir
    dir = parentDir(dir)

proc loadDecisionState(decisionPath: string): Table[string, string] =
  ## Returns { invariant -> PASS/FAIL/UNPROVEN } from decision.independent.*.json invariantResults.
  let node = parseFile(decisionPath)
  if node.hasKey("invariantResults") and node["invariantResults"].kind == JObject:
    for k, v in node["invariantResults"]:
      if v.kind == JObject and v.hasKey("result") and v["result"].kind == JString:
        result[k] = v["result"].getStr

proc evalPredicate(pred: string; states: seq[string]): bool =
  ## Evaluate one of the FIXED predicate tokens over the resolved evidence states.
  case pred
  of "EVIDENCE_ALL_SATISFIED":
    states.len > 0 and states.allIt(it == "PASS")
  of "EVIDENCE_ANY_SATISFIED":
    states.anyIt(it == "PASS")
  of "NO_BLOCKER_IN_REQUIRED_SET":
    not states.anyIt(it == "FAIL")
  else:
    false

proc latestDecision(root: string): string =
  ## Return the newest data/readiness/decision.independent.*.json by filename (chronological order).
  let dir = root / "data" / "readiness"
  var best = ""
  for kind, path in walkDir(dir):
    if kind == pcFile and extractFilename(path).startsWith("decision.independent.") and
       extractFilename(path).endsWith(".json"):
      if best == "" or extractFilename(path) > extractFilename(best):
        best = path
  best

proc main() =
  let root = repoRoot()
  let reqPath = root / "data" / "readiness" / "launch_requirements.json"
  let decisionPath = latestDecision(root)
  let closurePath = root / "data" / "readiness" / "closure_state.json"
  let outPath = root / "data" / "readiness" / "launch_evaluation.json"

  if not fileExists(reqPath):
    stderr.writeLine("launch_evaluation: missing launch_requirements.json"); quit(1)
  if decisionPath.len == 0 or not fileExists(decisionPath):
    stderr.writeLine("launch_evaluation: no decision.independent.*.json found"); quit(1)

  let reqs = parseFile(reqPath)
  let decStates = loadDecisionState(decisionPath)

  var perRequirement = newJObject()
  var launchAllSatisfied = true      ## Overall = AND over status=="REQUIRED" only
  var hardeningSatisfied = true      ## Integrity-Hardening = report-only, no Overall impact
  var hardeningTotal = 0
  var hardeningSatisfiedCount = 0
  var launchTotal = 0
  var launchSatisfiedCount = 0

  if reqs.hasKey("requirements") and reqs["requirements"].kind == JObject:
    for cap, spec in reqs["requirements"]:
      var evidence: seq[string] = @[]
      var predicate = "EVIDENCE_ALL_SATISFIED"
      var closureNote = ""
      var status = "REQUIRED"  ## derived from Entry Contract §2 status; default REQUIRED
      if spec.kind == JObject:
        if spec.hasKey("requiredEvidence") and spec["requiredEvidence"].kind == JArray:
          for e in spec["requiredEvidence"]:
            if e.kind == JString: evidence.add(e.getStr)
        if spec.hasKey("predicate") and spec["predicate"].kind == JString:
          predicate = spec["predicate"].getStr
        if spec.hasKey("requiredClosureState") and spec["requiredClosureState"].kind == JString:
          closureNote = spec["requiredClosureState"].getStr
        if spec.hasKey("status") and spec["status"].kind == JString:
          status = spec["status"].getStr

      # Resolve each evidence id to a decision state, then evaluate.
      var states: seq[string] = @[]
      var blockers: seq[string] = @[]
      for e in evidence:
        let p = parentInvariant(e)
        let st = if decStates.hasKey(p): decStates[p] else: "UNPROVEN"
        states.add(st)
        if st != "PASS":
          blockers.add(e & "=" & st)
      let satisfied = evalPredicate(predicate, states)

      if status == "HARDENING":
        # Integrity-Hardening: reported only — NEVER affects the Overall launch verdict.
        hardeningTotal += 1
        if satisfied: hardeningSatisfiedCount += 1
        if not satisfied: hardeningSatisfied = false
      else:
        # REQUIRED (Launch-Critical): participates in the Overall launch verdict.
        launchTotal += 1
        if satisfied: launchSatisfiedCount += 1
        if not satisfied: launchAllSatisfied = false

      var capObj = newJObject()
      capObj["satisfied"] = %(satisfied)
      capObj["status"] = %status
      var bArr = newJArray()
      for b in blockers: bArr.add(%b)
      capObj["blockers"] = bArr
      capObj["evidenceStates"] = %(states)
      if closureNote.len > 0: capObj["closureStateSecondary"] = %closureNote
      perRequirement[cap] = capObj

  var verdict = newJObject()
  verdict["launchStatus"] = %(if launchAllSatisfied: "GO" else: "NO-GO")
  verdict["model"] = %"binary GO/NO-GO over Launch-Critical (status=REQUIRED) layer; Integrity-Hardening reported separately and does not affect the verdict"
  verdict["note"] = %(if launchAllSatisfied: "all Launch-Critical requirements satisfied" else:
    "one or more Launch-Critical requirements not satisfied")

  # 2-Layer: Integrity-Hardening is a separate, report-only layer (CERT-* predicates).
  # NOT_EVALUATED when no hardening requirement is present in the registry.
  var hardeningStatus = "NOT_EVALUATED"
  if hardeningTotal > 0:
    hardeningStatus = (if hardeningSatisfied: "SATISFIED" else: "UNSATISFIED")

  var resultObj = newJObject()
  resultObj["contractVersion"] = %(if reqs.hasKey("contractVersion"): reqs["contractVersion"].getStr else: "v1")
  resultObj["decisionSource"] = %extractFilename(decisionPath)
  resultObj["perRequirement"] = perRequirement
  resultObj["verdict"] = verdict
  resultObj["layers"] = %*{
    "launchCritical": {
      "count": launchTotal,
      "satisfiedCount": launchSatisfiedCount,
      "allSatisfied": launchAllSatisfied
    },
    "integrityHardening": {
      "state": hardeningStatus,
      "count": hardeningTotal,
      "satisfiedCount": hardeningSatisfiedCount
    }
  }

  writeFile(outPath, pretty(resultObj) & "\n")
  # Deterministic readout to stdout
  for cap in perRequirement.keys:
    stdout.writeLine(cap & " [" & perRequirement[cap]["status"].getStr & "] -> satisfied=" & $perRequirement[cap]["satisfied"].getBool)
  stdout.writeLine("LAUNCH_CRITICAL=" & $launchSatisfiedCount & "/" & $launchTotal)
  stdout.writeLine("HARDENING_STATUS=" & hardeningStatus)
  stdout.writeLine("LAUNCH_VERDICT=" & resultObj["verdict"]["launchStatus"].getStr)
  stdout.writeLine("WRITTEN=" & outPath)

when isMainModule:
  main()
