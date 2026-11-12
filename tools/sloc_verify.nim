import std/[json, os, strutils, strformat, hashes, sets, options]
import compiler/[ast, idents]
import core/ast_kernel
import core/sloc_policy
import core/results
import core/crypto/hash_kernel

type
  VerifyStep* = enum
    vsFixtureIntegrity
    vsEvidenceIdentity
    vsCurrentObservation
    vsPolicyCoverage
    vsEvidenceMatch
    vsPolicyVersion

  VerifyError* = object
    step*: VerifyStep
    evidenceId*: string
    message*: string

func classifyWhenCondition*(n: PNode): string {.raises: [].} =
  if evalWhenConditionAST(n).isSome:
    "when"
  elif evalWhenConditionCtx(n, WhenContext()).isSome:
    "when-context"
  else:
    "when-unknown"

func classifyWhenStmt*(n: PNode): string {.raises: [].} =
  var hasUnknown = false
  var hasContext = false
  for i in 0 ..< n.safeLen:
    let branch = n[i]
    if branch.kind == nkElifBranch and branch.safeLen >= 2:
      let cond = branch[0]
      let cat = classifyWhenCondition(cond)
      if cat == "when-unknown":
        hasUnknown = true
      elif cat == "when-context":
        hasContext = true
    elif branch.kind == nkElse:
      discard
  if hasUnknown:
    "when-unknown"
  elif hasContext:
    "when-context"
  else:
    "when"

func classifyNode*(n: PNode): HashSet[string] {.raises: [].} =
  if n.isNil:
    return result
  case n.kind
  of nkProcDef, nkFuncDef, nkTemplateDef, nkMacroDef, nkMethodDef,
     nkConverterDef, nkIteratorDef:
    result.incl("declaration")
  of nkCommentStmt:
    result.incl("comment")
  of nkWhenStmt:
    result.incl(classifyWhenStmt(n))
  of nkImportStmt:
    result.incl("import")
  else:
    discard
  for i in 0 ..< n.safeLen:
    let childCats = classifyNode(n[i])
    for c in childCats:
      result.incl(c)

proc extractCategories*(src: string): Result[HashSet[string], string] =
  let parsed = parseSourceToPNode(src)
  if parsed.isErr:
    return err(&"Parse failed: {parsed.error}")
  ok(classifyNode(parsed.get))

proc getRatifiedCategories*(registry: JsonNode): HashSet[string] =
  if registry.hasKey("rules") and registry["rules"].kind == JArray:
    for rule in registry["rules"]:
      if rule.hasKey("semantic_category") and rule["semantic_category"].kind == JString:
        result.incl(rule["semantic_category"].str)

proc parseWhenContext*(ctx: JsonNode): WhenContext =
  if ctx.isNil or ctx.kind == JNull:
    return WhenContext()
  let defs = ctx["defines"]
  var knownDef: HashSet[string]
  var knownUndef: HashSet[string]
  if defs != nil and defs.kind == JObject:
    for k in defs["knownDefined"]:
      if k.kind == JString:
        knownDef.incl(k.str)
    for k in defs["knownUndefined"]:
      if k.kind == JString:
        knownUndef.incl(k.str)
  var tc: Option[string]
  var tcpu: Option[string]
  var copts: HashSet[string]
  if ctx["targetOS"] != nil and ctx["targetOS"].kind == JString:
    tc = some(ctx["targetOS"].str)
  if ctx["targetCPU"] != nil and ctx["targetCPU"].kind == JString:
    tcpu = some(ctx["targetCPU"].str)
  if ctx["compileOptions"] != nil and ctx["compileOptions"].kind == JArray:
    for c in ctx["compileOptions"]:
      if c.kind == JString:
        copts.incl(c.str)
  WhenContext(
    defines: DefineContext(knownDefined: knownDef, knownUndefined: knownUndef),
    targetOS: tc,
    targetCPU: tcpu,
    compileOptions: copts
  )

proc step1FixtureIntegrity*(src: string; expectedHash: string): Result[bool, string] =
  let actualHash = sha256Hex(src)
  if actualHash != expectedHash:
    err(&"Fixture hash mismatch: expected {expectedHash}, got {actualHash}")
  else:
    ok(true)

proc step2EvidenceIdentity*(evMetric: string; evContext: JsonNode; currentMetric: string; currentCtx: Option[WhenContext]): Result[bool, string] =
  if evMetric != currentMetric:
    err(&"Metric mismatch: evidence={evMetric}, current={currentMetric}")
  elif evContext != nil and evContext.kind == JObject and currentCtx.isSome:
    let evDefs = evContext["defines"]
    let curDefs = currentCtx.get().defines
    var evKnown: HashSet[string]
    var evUnknown: HashSet[string]
    if evDefs != nil and evDefs.kind == JObject:
      for k in evDefs["knownDefined"]:
        if k.kind == JString: evKnown.incl(k.str)
      for k in evDefs["knownUndefined"]:
        if k.kind == JString: evUnknown.incl(k.str)
    if evKnown != curDefs.knownDefined or evUnknown != curDefs.knownUndefined:
      err(&"Context mismatch: evidence defines known={evKnown}, unknown={evUnknown}; current known={curDefs.knownDefined}, unknown={curDefs.knownUndefined}")
    else:
      ok(true)
  else:
    ok(true)

proc step3CurrentObservation*(src: string; metric: string; ctx: Option[WhenContext]): Result[string, string] =
  let parsed = parseSourceToPNode(src)
  if parsed.isErr:
    return err(&"Parse failed: {parsed.error}")
  let node = parsed.get()
  if metric == "sourceSloc":
    let sloc = sourceSloc(node)
    ok($sloc)
  elif metric == "effectiveSloc":
    if ctx.isNone:
      let r = effectiveSloc(node, WhenContext())
      if r.isErr:
        ok(&"err:{r.error}")
      else:
        ok($r.get)
    else:
      let r = effectiveSloc(node, ctx.get)
      if r.isErr:
        ok(&"err:{r.error}")
      else:
        ok($r.get)
  else:
    err(&"Unknown metric: {metric}")

proc requiredRuleForObservation*(metric: string; obsResult: string): string =
  if metric == "sourceSloc":
    "SLOC-PROC-DECL"
  elif metric == "effectiveSloc":
    if obsResult.startsWith("err:"):
      "SLOC-WHEN-UNKNOWN"
    else:
      "SLOC-WHEN-TIER1"
  else:
    ""

proc step4PolicyCoverage*(policyRefs: seq[string]; registryRules: seq[string]; metric: string; obsResult: string; src: string; registry: JsonNode): Result[bool, string] =
  for pref in policyRefs:
    var found = false
    for rule in registryRules:
      if rule == pref:
        found = true
        break
    if not found:
      return err(&"Unknown rule in policy_refs: {pref} not found in registry")
  let reqRule = requiredRuleForObservation(metric, obsResult)
  if reqRule != "":
    var found = false
    for rule in registryRules:
      if rule == reqRule:
        found = true
        break
    if not found:
      return err(&"Unknown semantic pattern: observation requires rule {reqRule} which is not in registry")
  let catResult = extractCategories(src)
  if catResult.isErr:
    return err(&"Category extraction failed: {catResult.error}")
  let currentCategories = catResult.get()
  let ratifiedCategories = getRatifiedCategories(registry)
  for cat in currentCategories:
    if cat notin ratifiedCategories:
      return err(&"Unratified semantic usage: category '{cat}' not found in ratified policy")
  ok(true)

proc step5EvidenceMatch*(currentResult: string; expectedResult: JsonNode): Result[bool, string] =
  if expectedResult == nil or expectedResult.kind == JNull:
    return err("Missing evidence: no expected_result to match against")
  if expectedResult.kind == JString and expectedResult.str.startsWith("err:"):
    let expectedErr = expectedResult.str
    if not currentResult.startsWith("err:"):
      return err(&"Expected error {expectedErr} but got success: {currentResult}")
    if currentResult != expectedErr:
      return err(&"Error mismatch: expected {expectedErr}, got {currentResult}")
    ok(true)
  elif expectedResult.kind == JInt:
    if currentResult.startsWith("err:"):
      return err(&"Expected result {expectedResult.num} but got error: {currentResult}")
    let currentVal = parseInt(currentResult)
    if currentVal != expectedResult.num:
      return err(&"Result mismatch: expected {expectedResult.num}, got {currentVal}")
    ok(true)
  elif expectedResult.kind == JObject and expectedResult.hasKey("error"):
    let expectedErr = "err:" & expectedResult["error"].str
    if not currentResult.startsWith("err:"):
      return err(&"Expected error {expectedErr} but got success: {currentResult}")
    if currentResult != expectedErr:
      return err(&"Error mismatch: expected {expectedErr}, got {currentResult}")
    ok(true)
  else:
    err(&"Invalid expected_result type in evidence")

proc step6PolicyVersion*(evPolicyVersion: string; registryPolicyVersion: string): Result[bool, string] =
  if evPolicyVersion != registryPolicyVersion:
    err(&"Policy version mismatch: evidence={evPolicyVersion}, registry={registryPolicyVersion}")
  else:
    ok(true)

proc loadRegistry*(path: string): Result[JsonNode, string] =
  if not fileExists(path):
    return err(&"Registry not found: {path}")
  let content = readFile(path)
  let parsed = parseJson(content)
  if parsed.kind != JObject:
    return err("Registry root must be a JSON object")
  ok(parsed)

proc loadEvidence*(path: string): Result[JsonNode, string] =
  if not fileExists(path):
    return err(&"Evidence not found: {path}")
  let content = readFile(path)
  let parsed = parseJson(content)
  if parsed.kind != JArray:
    return err("Evidence root must be a JSON array")
  ok(parsed)

proc getRegistryRules*(registry: JsonNode): seq[string] =
  result = @[]
  if registry.hasKey("rules") and registry["rules"].kind == JArray:
    for rule in registry["rules"]:
      if rule.hasKey("rule_id") and rule["rule_id"].kind == JString:
        result.add(rule["rule_id"].str)

proc verifyEntry*(ev: JsonNode; registry: JsonNode): Result[bool, seq[string]] =
  var errors: seq[string]
  let evId = if ev.hasKey("id") and ev["id"].kind == JString: ev["id"].str else: "unknown"
  let src = if ev.hasKey("fixture_source") and ev["fixture_source"].kind == JString: ev["fixture_source"].str else: ""
  let hash = if ev.hasKey("fixture_raw_sha256") and ev["fixture_raw_sha256"].kind == JString: ev["fixture_raw_sha256"].str else: ""
  let metric = if ev.hasKey("metric") and ev["metric"].kind == JString: ev["metric"].str else: ""
  let ctxNode = if ev.hasKey("context"): ev["context"] else: nil
  let expectedResult = if ev.hasKey("expected_result"): ev["expected_result"] else: nil
  let policyRefs = if ev.hasKey("policy_refs") and ev["policy_refs"].kind == JArray:
    var refs: seq[string]
    for r in ev["policy_refs"]:
      if r.kind == JString: refs.add(r.str)
    refs
  else: @[]
  let ratifiedPolicyVersion = if ev.hasKey("ratified_policy_version") and ev["ratified_policy_version"].kind == JString: ev["ratified_policy_version"].str else: ""
  let registryPolicyVersion = if registry.hasKey("policy_version") and registry["policy_version"].kind == JString: registry["policy_version"].str else: ""
  let registryRules = getRegistryRules(registry)

  let r1 = step1FixtureIntegrity(src, hash)
  if r1.isErr:
    errors.add(&"[{evId}] step1 fixture integrity: {r1.error}")

  let curCtx = if ctxNode != nil and ctxNode.kind == JObject: some(parseWhenContext(ctxNode)) else: none(WhenContext)
  let r2 = step2EvidenceIdentity(metric, ctxNode, metric, curCtx)
  if r2.isErr:
    errors.add(&"[{evId}] step2 evidence identity: {r2.error}")

  let r3 = step3CurrentObservation(src, metric, curCtx)
  if r3.isErr:
    errors.add(&"[{evId}] step3 current observation: {r3.error}")

  if r3.isOk:
    let r4 = step4PolicyCoverage(policyRefs, registryRules, metric, r3.get, src, registry)
    if r4.isErr:
      errors.add(&"[{evId}] step4 policy coverage: {r4.error}")

    if expectedResult != nil:
      let r5 = step5EvidenceMatch(r3.get, expectedResult)
      if r5.isErr:
        errors.add(&"[{evId}] step5 evidence match: {r5.error}")

  let r6 = step6PolicyVersion(ratifiedPolicyVersion, registryPolicyVersion)
  if r6.isErr:
    errors.add(&"[{evId}] step6 policy version: {r6.error}")

  if errors.len > 0:
    err(errors)
  else:
    ok(true)

proc verifyAll*(): Result[bool, seq[string]] =
  let registryPath = "data/sloc_policy_registry.json"
  let evidencePath = "tests/sloc/evidence/evidence.json"
  let regResult = loadRegistry(registryPath)
  if regResult.isErr:
    return err(@[regResult.error])
  let evResult = loadEvidence(evidencePath)
  if evResult.isErr:
    return err(@[evResult.error])
  let registry = regResult.get()
  let evidence = evResult.get()
  var allErrors: seq[string]
  for ev in evidence:
    let r = verifyEntry(ev, registry)
    if r.isErr:
      allErrors.add(r.error)
  if allErrors.len > 0:
    err(allErrors)
  else:
    ok(true)

when isMainModule:
  let result = verifyAll()
  if result.isErr:
    for err in result.error:
      stderr.writeLine &"FAIL: {err}"
    quit(1)
  else:
    echo "All SLOC verification checks passed."
    quit(0)
