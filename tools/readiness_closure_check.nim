## tools/readiness_closure_check.nim — deterministic, dependency-free readiness-closure validator.
##
## Loads data/readiness/closure_state.json (the per-blocker ReadinessClosureRecord
## ledger) and data/readiness/closure_state.schema.json (the reference contract,
## validated for existence/parse only — this repo has no JSON-Schema draft-07
## engine, so the checks are a structural mirror of the schema + the normative
## spec docs/design/readiness_closure_protocol.md).
##
## Every check is deterministic: no timestamps, no randomness, no network, no
## src/core imports (import encapsulation; standalone tool). stdlib only.
##
## Exit: 0 = all valid; 1 = invalid (failure listing on stdout).
## CLI: readiness_closure_check [closureStatePath] [newerDecisionPath] [olderDecisionPath]
##      Paths default to repo-root-relative canonical locations.

import std/[json, os, strutils, tables]

type
  Failure = object
    invariant: string
    rule: string
    detail: string

# ---------------------------------------------------------------------------
# Enums (mirror the schema / spec)
# ---------------------------------------------------------------------------
const
  ForwardStates = ["OBSERVED", "CLASSIFIED", "SEMANTICALLY_RATIFIED", "CONTRACT_REVISION_RATIFIED",
    "IMPLEMENTED", "INDEPENDENTLY_REEVALUATED", "CLOSED"]
  BlockedStates = ["BLOCKED_BY_DECISION", "BLOCKED_BY_RESEARCH", "BLOCKED_BY_IMPLEMENTATION"]
  AllStates = ["OBSERVED", "CLASSIFIED", "SEMANTICALLY_RATIFIED", "CONTRACT_REVISION_RATIFIED",
               "IMPLEMENTED", "INDEPENDENTLY_REEVALUATED", "CLOSED",
               "BLOCKED_BY_DECISION", "BLOCKED_BY_RESEARCH", "BLOCKED_BY_IMPLEMENTATION"]
  AllClasses = ["SEMANTIC_DECISION", "CONTRACT_ARCHITECTURE_DECISION",
                "BOUNDARY_NON_GOAL", "RESEARCH", "IMPLEMENTATION"]
  # blockerClass -> pinned blocked state
  PinTable = {"RESEARCH": "BLOCKED_BY_RESEARCH",
              "IMPLEMENTATION": "BLOCKED_BY_IMPLEMENTATION"}.toTable
  Sha64 = ['0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f']

proc isHex(s: string; n: int): bool =
  if s.len != n: return false
  for c in s:
    if c notin Sha64: return false
  true

proc safeGet(o: JsonNode; key: string): JsonNode =
  ## nil-safe get: returns a non-nil JNull node when o is nil, not an object,
  ## or the key is absent. Never returns nil.
  if o == nil or o.kind != JObject:
    return newJNull()
  if not o.hasKey(key):
    return newJNull()
  o[key]

proc repoRoot(): string =
  ## Robust repo-root resolution: try the binary's up-tree containing config.nims.
  var dir = getAppDir()
  for _ in 0 .. 3:
    if fileExists(dir / "config.nims"):
      return dir
    dir = parentDir(dir)
  quit(1)

# ---------------------------------------------------------------------------
# Collectors
# ---------------------------------------------------------------------------

var failures: seq[Failure] = @[]
var readout: seq[string] = @[]

proc fail(inv, rule, detail: string) =
  failures.add(Failure(invariant: inv, rule: rule, detail: detail))

proc isToBeComputed(v: JsonNode): bool =
  v.kind == JObject and v.hasKey("toBeComputedAt")

# ---------------------------------------------------------------------------
# Record checks
# ---------------------------------------------------------------------------

proc checkRecord(rec: JsonNode): string =
  ## Returns the invariant id; accumulates failures in the global `failures`.
  let inv = if rec.hasKey("invariant") and rec["invariant"].kind == JString:
      rec["invariant"].getStr else: "<unknown>"

  # --- rule-2: required fields
  const RequiredRec = ["currentState", "blockerClass", "status", "observedEvidenceDigest",
                       "ratification", "contractRevision", "implementationRevision",
                       "evaluationIdentity", "priorEvaluations", "predecessor",
                       "createdAt", "updatedAt"]
  for f in RequiredRec:
    if not rec.hasKey(f):
      fail(inv, "rule-2", "missing required field '" & f & "'")
  if not (rec.hasKey("invariant") and rec["invariant"].kind == JString and
          rec["invariant"].getStr.len > 0):
    fail(inv, "rule-3", "invariant must be a non-empty string")

  # --- rule-3: enum membership
  let st = if rec.hasKey("currentState") and rec["currentState"].kind == JString:
      rec["currentState"].getStr else: ""
  if st notin AllStates:
    fail(inv, "rule-3", "currentState '" & st & "' is not a valid ReadinessState")
  let cls = if rec.hasKey("blockerClass") and rec["blockerClass"].kind == JString:
      rec["blockerClass"].getStr else: ""
  if cls notin AllClasses:
    fail(inv, "rule-3", "blockerClass '" & cls & "' is not a valid BlockerClass")
  if rec.hasKey("status"):
    let status = rec["status"]
    if status.kind == JString and status.getStr notin ["active", "closed"]:
      fail(inv, "rule-3", "status must be 'active' or 'closed'")

  # --- rule-4: blockerClass <-> blocked-state pinning
  if st in BlockedStates:
    let pinned = PinTable.getOrDefault(cls, "")
    if pinned.len > 0 and st != pinned:
      fail(inv, "rule-4", "blockerClass '" & cls & "' pins to '" & pinned &
           "' but currentState is '" & st & "'")
    if cls == "SEMANTIC_DECISION" or cls == "CONTRACT_ARCHITECTURE_DECISION":
      if st != "BLOCKED_BY_DECISION":
        fail(inv, "rule-4", "blockerClass '" & cls & "' when blocked must rest in " &
             "BLOCKED_BY_DECISION (got '" & st & "')")

  # --- rule-5: ratify-before-implement
  if st != "CLOSED":
    let ratification = safeGet(rec, "ratification")
    let ratEmpty = ratification.kind != JArray or ratification.len == 0
    let cr = safeGet(rec, "contractRevision")
    let ir = safeGet(rec, "implementationRevision")
    let crSet = cr.kind == JString and cr.getStr.len > 0
    let irSet = ir.kind == JString and ir.getStr.len > 0
    if ratEmpty and (crSet or irSet):
      fail(inv, "rule-5", "ratify-before-implement violated: contract/implementation " &
           "revision set but ratification is empty")

  # --- rule-6: per-state required evidence
  case st
  of "BLOCKED_BY_DECISION":
    if not (rec.hasKey("pendingDecision") and rec["pendingDecision"].kind == JString and
            rec["pendingDecision"].getStr.len > 0):
      fail(inv, "rule-6", "BLOCKED_BY_DECISION requires a non-empty pendingDecision")
  of "BLOCKED_BY_RESEARCH":
    if not (rec.hasKey("researchReference") and rec["researchReference"].kind == JString and
            rec["researchReference"].getStr.len > 0):
      fail(inv, "rule-6", "BLOCKED_BY_RESEARCH requires a non-empty researchReference")
  of "SEMANTICALLY_RATIFIED", "CONTRACT_REVISION_RATIFIED", "IMPLEMENTED",
     "INDEPENDENTLY_REEVALUATED", "CLOSED":
    if not (rec.hasKey("ratification") and rec["ratification"].kind == JArray and
            rec["ratification"].len > 0):
      fail(inv, "rule-6", "state '" & st & "' requires non-empty ratification")
  else: discard
  if st in ["CONTRACT_REVISION_RATIFIED", "IMPLEMENTED", "CLOSED"]:
    if not (rec.hasKey("contractRevision") and rec["contractRevision"].kind == JString and
            rec["contractRevision"].getStr.len > 0):
      fail(inv, "rule-6", "state '" & st & "' requires a non-empty contractRevision")
  if st in ["IMPLEMENTED", "CLOSED"]:
    if not (rec.hasKey("implementationRevision") and
            rec["implementationRevision"].kind == JString and
            rec["implementationRevision"].getStr.len > 0):
      fail(inv, "rule-6", "state '" & st & "' requires a non-empty implementationRevision")

  # --- rule-6 (CLOSED): full evidence set
  if st == "CLOSED":
    let eiClosed = safeGet(rec, "evaluationIdentity")
    let okRat = rec.hasKey("ratification") and rec["ratification"].kind == JArray and
                rec["ratification"].len > 0
    let okCr = rec.hasKey("contractRevision") and rec["contractRevision"].kind == JString and
               rec["contractRevision"].getStr.len > 0
    let okIr = rec.hasKey("implementationRevision") and
               rec["implementationRevision"].kind == JString and
               rec["implementationRevision"].getStr.len > 0
    let okEi = eiClosed.kind == JObject and eiClosed.hasKey("computed") and
               eiClosed["computed"].kind == JBool and eiClosed["computed"].getBool == true
    if not (okRat and okCr and okIr and okEi):
      fail(inv, "rule-6", "CLOSED requires ratification + contractRevision + " &
           "implementationRevision + evaluationIdentity.computed==true")

  # --- rule-7: evaluationIdentity honesty (anti-theater: no fabricated digest)
  let ei = safeGet(rec, "evaluationIdentity")
  if ei.kind != JObject:
    fail(inv, "rule-7", "evaluationIdentity must be an object")
  elif ei.hasKey("computed"):
    let computed = ei["computed"].kind == JBool and ei["computed"].getBool
    let it = safeGet(ei, "inputTerms")
    if it.kind != JObject:
      fail(inv, "rule-7", "evaluationIdentity.inputTerms must be an object")
    else:
      if computed:
        # computed==true: every input term + evaluationInputIdentity + decisionIdentity
        # must be a REAL non-empty string (not a toBeComputedAt marker)
        for term in ["EvidenceDigest", "PolicyDigest", "EvaluatorArtifactDigest",
                     "SchemaDigest", "ExecutionContractDigest"]:
          let t = safeGet(it, term)
          if not (t.kind == JString and t.getStr.len > 0):
            fail(inv, "rule-7", "computed==true but input term '" & term &
                 "' is not a real digest string")
        for idk in ["evaluationInputIdentity", "decisionIdentity"]:
          let v = safeGet(ei, idk)
          if not (v.kind == JString and v.getStr.len > 0):
            fail(inv, "rule-7", "computed==true but '" & idk & "' is not a real string")
      else:
        # computed==false: terms that are NOT real digests must be toBeComputedAt
        # markers, never fabricated hex strings. Only EvidenceDigest/PolicyDigest/
        # EvaluatorArtifactDigest may be real hex.
        let termsToVerify = ["SchemaDigest", "ExecutionContractDigest"]
        for term in termsToVerify:
          let t = safeGet(it, term)
          if t.kind == JObject:
            if not t.hasKey("toBeComputedAt"):
              fail(inv, "rule-7", "computed==false but '" & term &
                   "' is a non-marker object (expected toBeComputedAt, not a fabricated digest)")
          elif t.kind == JString and t.getStr.len > 0:
            fail(inv, "rule-7", "computed==false but '" & term &
                 "' carries a fabricated digest string; must be toBeComputedAt")
          # Note: decisionIdentity/evaluationInputIdentity are at the ei level,
          # not inside inputTerms; handle them below.
        for idk in ["evaluationInputIdentity", "decisionIdentity"]:
          let v = safeGet(ei, idk)
          if v.kind == JObject:
            if not v.hasKey("toBeComputedAt"):
              fail(inv, "rule-7", "computed==false but '" & idk &
                   "' is a non-marker object (expected toBeComputedAt)")
          elif v.kind == JString and v.getStr.len > 0:
            fail(inv, "rule-7", "computed==false but '" & idk &
                 "' carries a fabricated digest; must be toBeComputedAt")

  # --- priorEvaluations non-empty
  if not (rec.hasKey("priorEvaluations") and rec["priorEvaluations"].kind == JArray and
          rec["priorEvaluations"].len > 0):
    fail(inv, "rule-2", "priorEvaluations must be a non-empty array")

  return inv

# ---------------------------------------------------------------------------
# Root + decision cross-check
# ---------------------------------------------------------------------------

proc latestEvidenceDigest(decisionPaths: seq[string]): string =
  ## Read each decision artifact (must exist), pick the newest by the UTC clock
  ## in its filename (*.T<HHMMSS>Z.json), return that file's evidenceManifestDigest.
  var bestStamp = ""
  var best = ""
  for p in decisionPaths:
    let base = extractFilename(p)
    # stamp = the T<HHMMSS>Z portion, e.g. "T122137Z" from decision.independent.20260819T122137Z.json
    var stamp = ""
    let tPos = base.find('T')
    if tPos >= 0:
      stamp = base[tPos .. ^6]  # strip trailing ".json" (5 chars)
    if not fileExists(p):
      fail("(cross-check)", "rule-8", "decision artifact not found: " & p)
      continue
    let node = try: parseFile(p) except CatchableError as e:
      fail("(cross-check)", "rule-8", "failed to parse " & p & ": " & e.msg)
      continue
    if node.hasKey("evidenceManifestDigest") and
       node["evidenceManifestDigest"].kind == JString:
      if stamp > bestStamp:
        bestStamp = stamp
        best = node["evidenceManifestDigest"].getStr
  if best.len == 0:
    fail("(cross-check)", "rule-8", "no evidenceManifestDigest recovered from decision artifacts")
  best

# ---------------------------------------------------------------------------
# Launch-registry checks (rule-L1) + R8 decomposition check (rule-L2)
# ---------------------------------------------------------------------------

proc checkLaunchRequirements(root: string; closureIds: seq[string];
                                 failures: var seq[Failure]) =
  ## rule-L1: data/readiness/launch_requirements.json must parse; every
  ## requirement's `predicate` token must be declared in the fixed
  ## `predicateVocabulary`; no requirement may reference R8-R (the research
  ## slice) -- it is not part of the v1 launch-requirement set.
  ## rule-L2: the closure ledger must not contain a bare "R8" record and
  ## must contain both decomposed records "R8-R" (research) and "R8-P" (product).
  let lrPath = root / "data" / "readiness" / "launch_requirements.json"
  if not fileExists(lrPath):
    failures.add(Failure(invariant: "(launch)", rule: "rule-L1",
      detail: "missing launch requirements registry: " & lrPath))
  else:
    var lr = newJNull()
    try:
      lr = parseFile(lrPath)
    except CatchableError as e:
      failures.add(Failure(invariant: "(launch)", rule: "rule-L1",
        detail: "launch_requirements.json does not parse as JSON: " & e.msg))
    if lr.kind == JObject:
      var vocab: seq[string] = @[]
      let v = safeGet(lr, "predicateVocabulary")
      if v.kind == JArray:
        for tok in v:
          if tok.kind == JString:
            vocab.add(tok.getStr)
      let reqs = safeGet(lr, "requirements")
      if reqs.kind == JObject:
        for name in reqs.keys:
          let rq = reqs[name]
          if rq.kind != JObject: continue
          let pred = safeGet(rq, "predicate")
          if pred.kind == JString and pred.getStr notin vocab:
            failures.add(Failure(invariant: name, rule: "rule-L1",
              detail: "predicate token '" & pred.getStr &
                "' is not declared in predicateVocabulary"))
          let ev = safeGet(rq, "requiredEvidence")
          if ev.kind == JArray:
            for tok in ev:
              if tok.kind == JString and tok.getStr == "R8-R":
                failures.add(Failure(invariant: name, rule: "rule-L1",
                  detail: "requiredEvidence references R8-R (research " &
                    "slice); R8-R is not in the v1 launch-requirement set"))
          let cs = safeGet(rq, "requiredClosureState")
          if cs.kind == JString and "R8-R" in cs.getStr:
            failures.add(Failure(invariant: name, rule: "rule-L1",
              detail: "requiredClosureState references R8-R; " &
                "R8-R is not in the v1 launch-requirement set"))
  # rule-L2: R8 decomposition in the closure ledger
  if "R8" in closureIds:
    failures.add(Failure(invariant: "(launch)", rule: "rule-L2",
      detail: "bare R8 record present; must decompose into R8-R and R8-P"))
  if "R8-R" notin closureIds:
    failures.add(Failure(invariant: "(launch)", rule: "rule-L2",
      detail: "missing R8-R (research) record in closure state"))
  if "R8-P" notin closureIds:
    failures.add(Failure(invariant: "(launch)", rule: "rule-L2",
      detail: "missing R8-P (product) record in closure state"))

proc main() =
  let root = repoRoot()
  var closurePath = root / "data" / "readiness" / "closure_state.json"
  var schemaPath = root / "data" / "readiness" / "closure_state.schema.json"
  var newerPath = root / "data" / "readiness" / "decision.independent.20260819T122137Z.json"
  var olderPath = root / "data" / "readiness" / "decision.independent.20260819T093022Z.json"

  let args = commandLineParams()
  if args.len >= 1: closurePath = if isAbsolute(args[0]): args[0] else: root / args[0]
  if args.len >= 2: newerPath = if isAbsolute(args[1]): args[1] else: root / args[1]
  if args.len >= 3: olderPath = if isAbsolute(args[2]): args[2] else: root / args[2]

  # schema must exist and parse as valid JSON (reference contract present)
  if not fileExists(schemaPath):
    fail("(schema)", "rule-1", "missing schema: " & schemaPath)
  else:
    try:
      discard parseFile(schemaPath)
    except CatchableError as e:
      fail("(schema)", "rule-1", "schema does not parse as JSON: " & e.msg)

  # load closure_state.json
  if not fileExists(closurePath):
    fail("(root)", "rule-1", "missing closure state: " & closurePath)
    # still emit the partial failure summary
    if failures.len > 0:
      for f in failures:
        stdout.writeLine(f.invariant & " [" & f.rule & "]: " & f.detail)
      quit(1)
    quit(1)

  let rootNode = try: parseFile(closurePath) except CatchableError as e:
    fail("(root)", "rule-1", "closure_state does not parse as JSON: " & e.msg)
    return

  # rule-1 envelope
  var ok = true
  if rootNode.kind != JObject: ok = false
  if not (rootNode.hasKey("schemaVersion") and rootNode["schemaVersion"].kind == JInt and
          rootNode["schemaVersion"].getInt == 1): ok = false
  if not (rootNode.hasKey("protocol") and rootNode["protocol"].kind == JString and
          rootNode["protocol"].getStr == "readiness-closure"): ok = false
  if not (rootNode.hasKey("records") and rootNode["records"].kind == JArray and
          rootNode["records"].len > 0): ok = false
  if not ok:
    fail("(root)", "rule-1", "top-level envelope invalid: need schemaVersion==1, " &
         "protocol=='readiness-closure', non-empty records[]")

  # rule-8 cross-check: observedEvidenceDigest == latest decision's evidenceManifestDigest
  let expectedDigest = latestEvidenceDigest(@[newerPath, olderPath])

  var seen: seq[string] = @[]
  if rootNode.hasKey("records") and rootNode["records"].kind == JArray:
    for rec in rootNode["records"]:
      let inv = checkRecord(rec)
      # uniqueness
      if inv in seen: fail(inv, "rule-3", "duplicate invariant id")
      seen.add(inv)
      # readout
      var st = ""
      var cls = ""
      if rec.hasKey("currentState") and rec["currentState"].kind == JString:
        st = rec["currentState"].getStr
      if rec.hasKey("blockerClass") and rec["blockerClass"].kind == JString:
        cls = rec["blockerClass"].getStr
      readout.add(inv & "=" & st & "/" & cls)
      # observedEvidenceDigest cross-check
      if rec.hasKey("observedEvidenceDigest"):
        let oed = rec["observedEvidenceDigest"]
        if oed.kind == JString and expectedDigest.len > 0 and oed.getStr != expectedDigest:
          fail(inv, "rule-8", "observedEvidenceDigest " & oed.getStr &
               " does not match latest decision evidenceManifestDigest " & expectedDigest)

  # Launch-requirement registry + R8-R/R8-P decomposition validation
  checkLaunchRequirements(root, seen, failures)

  # Output
  stdout.writeLine(readout.join("; "))
  if failures.len == 0:
    stdout.writeLine("ALL VALID")
    quit(0)
  else:
    for f in failures:
      stdout.writeLine(f.invariant & " [" & f.rule & "]: " & f.detail)
    stdout.writeLine("INVALID (" & $failures.len & " failure(s))")
    quit(1)

when isMainModule:
  main()
